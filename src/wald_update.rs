// Waldlust 새 버전 확인·앱 안 업데이트(명세 DSK-01 — 결정 D37, 2026-10-23 사용자 결정): 데스크탑 양방향(직원용) macOS·Windows 만.
// - 확인: 어드민 공개 `/api/app/latest`(heartbeat 와 같은 서버). 시작 때·12시간마다, 그리고 화면이 부를 때(설정 > 정보).
// - 받기: latest 의 `download`(`/api/app/download/<id>`)를 앱 로그인 토큰(Bearer — `access_token`)으로 받으며 SHA-256 을 재고
//   latest 의 `sha256` 과 대조한다. 토큰이 없거나 401 이면 `login`(화면이 로그인을 권하거나 어드민 페이지를 연다).
// - 설치: Windows 는 Inno 설치 파일을 조용히 실행(`/WALDUPDATE=1` — 설치 뒤 트레이·메인 창을 로그인 사용자로 다시 띄운다,
//   res/inno/waldlust.iss). macOS 는 dmg 안 앱의 번들 ID·서명·Team ID 를 지금 앱과 대조해 실행 중인 번들과 바꾸고,
//   이 프로세스가 끝나면 새 앱을 여는 도우미를 띄운 뒤 화면에 끝내라고(`quit`) 알린다.
// 화면(Flutter)과는 main_get_common/main_set_common 의 `wald-update-*` 키로 주고받고(src/flutter_ffi.rs), 확인 결과는
// `wald_update_state` 이벤트로도 보낸다. 모두 화면 프로세스에서 돈다(토큰이 그 사용자의 LocalConfig 에 있다).
use hbb_common::{
    config::LocalConfig,
    get_time, get_version_number, log,
    sha2::{Digest, Sha256},
};
use std::{
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
    time::Duration,
};
#[cfg(target_os = "macos")]
use std::process::Command;

#[derive(Clone, Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Latest {
    version: String,
    sha256: String,
    size: u64,
    file_name: String,
    /// 받기 전체 주소 — 비면 앱 안 업데이트를 할 수 없다(해시가 없거나 직원용이 아님 → 어드민 페이지)
    download: String,
    /// 어드민 '원격 설치 파일'·'업데이트 내역' 전체 주소
    page: String,
    changelog: String,
}

#[derive(Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Job {
    /// idle | downloading | verifying | ready | installing | installed | quit | error
    state: &'static str,
    /// 받는(받은) 버전
    version: String,
    total: u64,
    done: u64,
    /// state=error 일 때 화면이 번역할 코드: login | unavailable | network | hash | verify | location | denied | install
    error: &'static str,
    detail: String,
    #[serde(skip)]
    file: Option<PathBuf>,
}

#[derive(Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct State {
    /// 마지막 확인 결과: ""(아직) | checking | available | latest | error
    status: &'static str,
    latest: Option<Latest>,
    /// 마지막 확인 시각(유닉스 ms)
    checked_at: i64,
    error: String,
    job: Job,
}

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Default::default();
}
static CHECKING: AtomicBool = AtomicBool::new(false);
static DOWNLOADING: AtomicBool = AtomicBool::new(false);
static CANCEL: AtomicBool = AtomicBool::new(false);

fn work_dir() -> PathBuf {
    std::env::temp_dir().join("waldlust-update")
}

/// heartbeat 주소의 출처(scheme://host[:port]).
fn origin() -> Option<&'static str> {
    let url = crate::common::WALDLUST_HEARTBEAT_URL;
    let i = url.find("://")?;
    Some(match url[i + 3..].find('/') {
        Some(j) => &url[..i + 3 + j],
        None => url,
    })
}

/// 토큰은 https 이거나 이 PC(목업 어드민)일 때만 보낸다.
fn secure(url: &str) -> bool {
    url.starts_with("https://")
        || url.starts_with("http://127.0.0.1:")
        || url.starts_with("http://localhost:")
}

fn set_job(state: &'static str) {
    STATE.lock().unwrap().job.state = state;
}

fn fail(code: &'static str, detail: impl Into<String>) {
    let detail = detail.into();
    log::warn!("wald update: {code} {detail}");
    let job = &mut STATE.lock().unwrap().job;
    job.state = "error";
    job.error = code;
    job.detail = detail;
}

/// 시작 때 한 번(화면 프로세스 — common.rs check_software_update): 지난 업데이트의 임시 파일을 지우고, 바로 묻고, 그 뒤 12시간마다.
/// Windows 설치본은 heartbeat 를 서비스 프로세스가 보내 화면으로 전할 길이 없어서 화면 프로세스가 직접 묻는다.
pub fn start() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        std::thread::spawn(|| {
            let _ = std::fs::remove_dir_all(work_dir());
            loop {
                check();
                std::thread::sleep(Duration::from_secs(12 * 3600));
            }
        });
    });
}

/// 어드민 `/api/app/latest` 에서 이 앱이 쓰는 설치 파일의 최신 게시 버전을 받아 상태에 두고 화면에 `wald_update_state` 를 보낸다.
fn check() {
    if CHECKING.swap(true, Ordering::SeqCst) {
        return;
    }
    STATE.lock().unwrap().status = "checking";
    let r = fetch_latest();
    CHECKING.store(false, Ordering::SeqCst);
    {
        let mut s = STATE.lock().unwrap();
        s.checked_at = get_time();
        match r {
            Ok(Some(l)) if get_version_number(&l.version) > get_version_number(crate::VERSION) => {
                log::info!("wald update: {} -> {} ({})", crate::VERSION, l.version, l.page);
                s.status = "available";
                s.latest = Some(l);
                s.error.clear();
            }
            Ok(l) => {
                s.status = "latest";
                s.latest = l;
                s.error.clear();
            }
            Err(e) => {
                log::warn!("wald update check: {e}");
                s.status = "error";
                s.error = e;
            }
        }
    }
    #[cfg(feature = "flutter")]
    {
        let mut v = serde_json::to_value(&*STATE.lock().unwrap()).unwrap_or_default();
        v["name"] = "wald_update_state".into();
        v["current"] = crate::VERSION.into();
        let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, v.to_string());
    }
}

fn fetch_latest() -> Result<Option<Latest>, String> {
    let origin = origin().ok_or("no admin origin")?;
    let url = format!(
        "{origin}/api/app/latest?os={}&variant={}&arch={}",
        std::env::consts::OS,
        crate::wald_variant::name(),
        std::env::consts::ARCH
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| e.to_string())?;
    let v = client
        .get(&url)
        .send()
        .and_then(|r| r.error_for_status())
        .and_then(|r| r.json::<serde_json::Value>())
        .map_err(|e| e.to_string())?;
    let Some(version) = v["version"].as_str().filter(|x| !x.is_empty()) else {
        return Ok(None);
    };
    // 어드민이 주는 경로는 같은 서버 안('/'로 시작)만 쓴다.
    let path = |k: &str, default: &str| {
        let p = v[k].as_str().filter(|p| p.starts_with('/')).unwrap_or(default);
        if p.is_empty() {
            String::new()
        } else {
            format!("{origin}{p}")
        }
    };
    let sha256 = v["sha256"]
        .as_str()
        .filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit()))
        .unwrap_or_default()
        .to_ascii_lowercase();
    // 해시가 없으면 받은 파일을 대조할 수 없어 앱 안 업데이트를 하지 않는다(어드민 페이지로).
    let download = if sha256.is_empty() { String::new() } else { path("download", "") };
    Ok(Some(Latest {
        version: version.to_owned(),
        sha256,
        size: v["size"].as_u64().unwrap_or_default(),
        file_name: v["fileName"].as_str().unwrap_or_default().to_owned(),
        download,
        page: path("page", "/installers"),
        changelog: path("changelog", "/changelog"),
    }))
}

/// 화면 → Rust(main_get_common). `wald-update-state` = 상태 JSON.
pub fn get_common(key: &str) -> String {
    if key != "wald-update-state" {
        return String::new();
    }
    let mut v = serde_json::to_value(&*STATE.lock().unwrap()).unwrap_or_default();
    v["current"] = crate::VERSION.into();
    v.to_string()
}

/// 화면 → Rust(main_set_common): `wald-update-check`·`wald-update-start`(받기)·`wald-update-cancel`·`wald-update-install`.
pub fn set_common(key: &str) {
    match key {
        "wald-update-check" => {
            std::thread::spawn(check);
        }
        "wald-update-start" => start_download(),
        "wald-update-cancel" => CANCEL.store(true, Ordering::SeqCst),
        "wald-update-install" => {
            std::thread::spawn(install);
        }
        _ => {}
    }
}

fn start_download() {
    // 확인 중(status=checking)이어도 지난 확인에서 받은 새 버전으로 받는다. 화면이 진행 상태를 기다리므로 어느 길이든 job 을 바꾼다.
    let latest = STATE.lock().unwrap().latest.clone();
    let Some(latest) =
        latest.filter(|l| get_version_number(&l.version) > get_version_number(crate::VERSION))
    else {
        return fail("unavailable", "no newer version");
    };
    if latest.download.is_empty() || !secure(&latest.download) {
        return fail("unavailable", latest.download);
    }
    let token = LocalConfig::get_option("access_token");
    if token.is_empty() {
        return fail("login", "");
    }
    if DOWNLOADING.swap(true, Ordering::SeqCst) {
        return; // 받는 중 — 화면은 그 진행 상태를 본다
    }
    CANCEL.store(false, Ordering::SeqCst);
    {
        let job = &mut STATE.lock().unwrap().job;
        *job = Job {
            state: "downloading",
            version: latest.version.clone(),
            total: latest.size,
            ..Default::default()
        };
    }
    std::thread::spawn(move || {
        match download(&latest, &token) {
            Ok(Some(file)) => {
                let job = &mut STATE.lock().unwrap().job;
                job.state = "ready";
                job.file = Some(file);
            }
            Ok(None) => set_job("idle"), // 취소
            Err((code, detail)) => fail(code, detail),
        }
        DOWNLOADING.store(false, Ordering::SeqCst);
    });
}

/// 받으면서 SHA-256 을 잰다. 취소하면 Ok(None).
fn download(l: &Latest, token: &str) -> Result<Option<PathBuf>, (&'static str, String)> {
    let net = |e: &dyn std::fmt::Display| ("network", e.to_string());
    let dir = work_dir();
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(|e| net(&e))?;
    let mut name: String = l
        .file_name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
        .collect();
    if name.trim_matches('.').is_empty() {
        name = format!("waldlust-update.{}", if cfg!(windows) { "exe" } else { "dmg" });
    }
    let path = dir.join(name);
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(30 * 60))
        .build()
        .map_err(|e| net(&e))?;
    let mut resp = client
        .get(&l.download)
        .bearer_auth(token)
        .send()
        .map_err(|e| net(&e))?;
    if resp.status() == reqwest::StatusCode::UNAUTHORIZED {
        return Err(("login", "401".to_owned()));
    }
    if !resp.status().is_success() {
        return Err(("network", resp.status().to_string()));
    }
    if let Some(n) = resp.content_length() {
        STATE.lock().unwrap().job.total = n;
    }
    let mut f = std::fs::File::create(&path).map_err(|e| net(&e))?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];
    let mut done = 0u64;
    loop {
        if CANCEL.load(Ordering::SeqCst) {
            drop(f);
            let _ = std::fs::remove_file(&path);
            log::info!("wald update: download cancelled");
            return Ok(None);
        }
        let n = resp.read(&mut buf).map_err(|e| net(&e))?;
        if n == 0 {
            break;
        }
        f.write_all(&buf[..n]).map_err(|e| net(&e))?;
        hasher.update(&buf[..n]);
        done += n as u64;
        STATE.lock().unwrap().job.done = done;
    }
    f.flush().map_err(|e| net(&e))?;
    drop(f);
    set_job("verifying");
    let got = format!("{:x}", hasher.finalize());
    if got != l.sha256 {
        let _ = std::fs::remove_file(&path);
        return Err(("hash", format!("{done} bytes, sha256 {}", &got[..12])));
    }
    log::info!("wald update: downloaded {} ({done} bytes)", path.display());
    Ok(Some(path))
}

fn install() {
    let (file, version) = {
        let job = &mut STATE.lock().unwrap().job;
        match job.file.clone() {
            Some(f) if job.state == "ready" => {
                job.state = "installing";
                (f, job.version.clone())
            }
            _ => return,
        }
    };
    // 다시 켜진 앱이 업데이트됐는지 본다(flutter/lib/common.dart checkUpdate).
    LocalConfig::set_option("wald-update-target".to_owned(), version);
    if let Err((code, detail)) = platform_install(&file) {
        LocalConfig::set_option("wald-update-target".to_owned(), String::new());
        fail(code, detail);
    }
}

/// Inno 설치 파일을 "open" 으로 실행한다. "runas" 로 띄우지 않는다 — Inno 가 스스로 권한을 올려야 처음 실행한 로그인 사용자로
/// 트레이·메인 창을 되살린다(`runasoriginaluser`, 부록 A-40 의 더블클릭 설치와 같은 경로). 설치 프로그램이 이 앱을 끄므로
/// (PrepareToInstall taskkill) 보통 이 프로세스는 기다리는 중에 끝난다. 설치 프로그램이 먼저 끝나면 UAC 취소·실패다.
#[cfg(target_os = "windows")]
fn platform_install(file: &Path) -> Result<(), (&'static str, String)> {
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::{
        errhandlingapi::GetLastError,
        handleapi::CloseHandle,
        processthreadsapi::GetExitCodeProcess,
        shellapi::{ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW},
        synchapi::WaitForSingleObject,
        winbase::INFINITE,
        winuser::SW_SHOWNORMAL,
    };
    let wide = |s: &std::ffi::OsStr| s.encode_wide().chain(Some(0)).collect::<Vec<u16>>();
    let log_file = work_dir().join("install.log");
    let params = format!(
        "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /WALDUPDATE=1 /LOG=\"{}\"",
        log_file.display()
    );
    let verb = wide("open".as_ref());
    let path = wide(file.as_os_str());
    let params = wide(params.as_ref());
    let mut info: SHELLEXECUTEINFOW = unsafe { std::mem::zeroed() };
    info.cbSize = std::mem::size_of::<SHELLEXECUTEINFOW>() as _;
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = verb.as_ptr();
    info.lpFile = path.as_ptr();
    info.lpParameters = params.as_ptr();
    info.nShow = SW_SHOWNORMAL;
    if unsafe { ShellExecuteExW(&mut info) } == 0 {
        let e = unsafe { GetLastError() };
        // 1223 = ERROR_CANCELLED(UAC 거절)
        return Err((if e == 1223 { "denied" } else { "install" }, format!("ShellExecuteEx {e}")));
    }
    log::info!("wald update: installer started {}", file.display());
    let process = info.hProcess as usize; // HANDLE 은 Send 가 아니다
    std::thread::spawn(move || {
        let h = process as winapi::um::winnt::HANDLE;
        let mut code = 0u32;
        unsafe {
            WaitForSingleObject(h, INFINITE);
            GetExitCodeProcess(h, &mut code);
            CloseHandle(h);
        }
        // 여기까지 왔으면 설치 프로그램이 이 앱을 끄지 않고 끝났다.
        LocalConfig::set_option("wald-update-target".to_owned(), String::new());
        if code == 0 {
            // 개발 실행(설치 폴더 밖 exe)이면 설치는 됐는데 이 프로세스가 남는다.
            set_job("installed");
        } else {
            fail("install", format!("exit {code}, log {}", log_file.display()));
        }
    });
    Ok(())
}

/// dmg 안 앱을 검증해 실행 중인 번들과 바꾼다. 바꾸는 동안 앱은 살아 있어 실패·암호 취소를 화면에 알릴 수 있다.
/// 업스트림 macos.rs 의 update 함수들은 `/Applications/Waldlust.app` 를 박아 두어 포크 번들 이름(`Waldlust 원격지원.app`)과
/// 맞지 않아 쓰지 않는다(명세 DSK-01).
#[cfg(target_os = "macos")]
fn platform_install(dmg: &Path) -> Result<(), (&'static str, String)> {
    let target = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.ancestors().nth(3).map(Path::to_path_buf))
        .filter(|p| p.extension().map_or(false, |x| x == "app"))
        .ok_or(("location", "not an app bundle".to_owned()))?;
    if target.starts_with("/Volumes") {
        return Err(("location", target.display().to_string()));
    }
    let mnt = work_dir().join("mnt");
    let _ = std::fs::create_dir_all(&mnt);
    run(Command::new("hdiutil")
        .args(["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint"])
        .arg(&mnt)
        .arg(dmg))
    .map_err(|e| ("install", e))?;
    let r = verify_and_replace(&mnt, &target);
    let _ = run(Command::new("hdiutil").arg("detach").arg(&mnt).arg("-force"));
    r?;
    // 이 프로세스가 끝나면(최대 30초) 새 앱을 연다. 메뉴 막대 '종료'는 같은 실행 파일의 자식만 끝내므로 sh 는 남는다.
    use std::os::unix::process::CommandExt;
    Command::new("/bin/sh")
        .args([
            "-c",
            r#"i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; open "$2""#,
            "sh",
        ])
        .arg(std::process::id().to_string())
        .arg(&target)
        .process_group(0)
        .spawn()
        .map_err(|e| ("install", e.to_string()))?;
    log::info!("wald update: replaced {}, quitting", target.display());
    set_job("quit");
    Ok(())
}

#[cfg(target_os = "macos")]
fn verify_and_replace(mnt: &Path, target: &Path) -> Result<(), (&'static str, String)> {
    let verify = |e: String| ("verify", e);
    let apps: Vec<PathBuf> = std::fs::read_dir(mnt)
        .map_err(|e| verify(e.to_string()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map_or(false, |x| x == "app"))
        .collect();
    let [app] = apps.as_slice() else {
        return Err(verify(format!("{} apps in dmg", apps.len())));
    };
    let bundle_id = |p: &Path| {
        run(Command::new("/usr/libexec/PlistBuddy")
            .args(["-c", "Print :CFBundleIdentifier"])
            .arg(p.join("Contents/Info.plist")))
        .map(|s| s.trim().to_owned())
    };
    let (new_id, cur_id) = (bundle_id(app).map_err(verify)?, bundle_id(target).map_err(verify)?);
    if new_id != cur_id {
        return Err(verify(format!("bundle id {new_id}")));
    }
    run(Command::new("codesign").args(["--verify", "--deep", "--strict"]).arg(app)).map_err(verify)?;
    // 정식판은 같은 Developer ID 팀, ad-hoc 시험판은 둘 다 'not set'.
    let team = |p: &Path| {
        let o = Command::new("codesign")
            .arg("-dv")
            .arg(p)
            .output()
            .map_err(|e| e.to_string())?;
        Ok::<_, String>(
            String::from_utf8_lossy(&o.stderr)
                .lines()
                .find_map(|l| l.strip_prefix("TeamIdentifier=").map(str::to_owned))
                .unwrap_or_default(),
        )
    };
    let (new_team, cur_team) = (team(app).map_err(verify)?, team(target).map_err(verify)?);
    if new_team != cur_team {
        return Err(verify(format!("team {new_team} != {cur_team}")));
    }
    // 같은 폴더 안에서 .wald-new 로 복사한 뒤 이름만 바꾼다. 실패하면 옛 번들을 되돌린다.
    const SCRIPT: &str = r#"set -e
src="$1"; dst="$2"; new="$dst.wald-new"; old="$dst.wald-old"
rm -rf "$new" "$old"
ditto "$src" "$new"
xattr -dr com.apple.quarantine "$new" 2>/dev/null || true
[ -n "$3" ] && chown -R "$3":staff "$new"
mv "$dst" "$old"
if ! mv "$new" "$dst"; then mv "$old" "$dst"; exit 1; fi
rm -rf "$old""#;
    let writable = |p: &Path| {
        use std::os::unix::ffi::OsStrExt;
        let Ok(c) = std::ffi::CString::new(p.as_os_str().as_bytes()) else {
            return false;
        };
        unsafe { hbb_common::libc::access(c.as_ptr(), hbb_common::libc::W_OK) == 0 }
    };
    let parent = target.parent().unwrap_or(Path::new("/"));
    if writable(parent) && writable(target) {
        let o = Command::new("/bin/sh")
            .args(["-c", SCRIPT, "sh"])
            .arg(app)
            .arg(target)
            .arg("")
            .output()
            .map_err(|e| ("install", e.to_string()))?;
        if !o.status.success() {
            return Err(("install", String::from_utf8_lossy(&o.stderr).into_owned()));
        }
        return Ok(());
    }
    // 쓸 수 없으면 관리자 암호를 묻는다(업스트림 update_me 와 같은 방식). 인자는 osascript argv 로 넘겨 AppleScript 따옴표를 피한다.
    let q = |s: &str| format!("'{}'", s.replace('\'', r"'\''"));
    let user = std::env::var("USER").unwrap_or_default();
    let cmd = format!(
        "/bin/sh -c {} sh {} {} {}",
        q(SCRIPT),
        q(&app.to_string_lossy()),
        q(&target.to_string_lossy()),
        q(&user)
    );
    let prompt = crate::lang::translate("wald-update-admin-prompt".to_owned());
    let o = Command::new("osascript")
        .args([
            "-e",
            "on run argv",
            "-e",
            "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
            "-e",
            "end run",
        ])
        .arg(cmd)
        .arg(prompt)
        .output()
        .map_err(|e| ("install", e.to_string()))?;
    if !o.status.success() {
        let err = String::from_utf8_lossy(&o.stderr).into_owned();
        // -128 = 사용자가 암호 창을 취소
        return Err((if err.contains("-128") { "denied" } else { "install" }, err));
    }
    Ok(())
}

/// 명령을 돌려 성공이면 표준 출력을, 실패면 상태·표준 오류를 준다.
#[cfg(target_os = "macos")]
fn run(cmd: &mut Command) -> Result<String, String> {
    let o = cmd.output().map_err(|e| format!("{cmd:?}: {e}"))?;
    if !o.status.success() {
        return Err(format!("{cmd:?}: {} {}", o.status, String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}
