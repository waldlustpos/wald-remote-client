// Waldlust 새 버전 확인·앱 안 업데이트(명세 DSK-01 — 결정 D37, 2026-10-23 사용자 결정): 데스크탑 양방향(직원용) macOS·Windows 만.
// - 확인: 어드민 공개 `/api/app/latest`(heartbeat 와 같은 서버). 시작 때·12시간마다, 그리고 화면이 부를 때(설정 > 정보).
// - 받기: latest 의 `download`(`/api/app/download/<id>`)를 앱 로그인 토큰(Bearer — `access_token`)으로 받으며 SHA-256 을 재고
//   latest 의 `sha256` 과 대조한다. 토큰이 없거나 401 이면 `login`(화면이 로그인을 권하거나 어드민 페이지를 연다).
// - 설치: Windows 는 Inno 설치 파일을 조용히 실행(`/WALDUPDATE=1` — 설치 뒤 트레이·메인 창을 로그인 사용자로 다시 띄운다,
//   res/inno/waldlust.iss). macOS 는 dmg 안 앱의 번들 ID·서명·Team ID 를 지금 앱과 대조해 실행 중인 번들과 바꾸고,
//   이 프로세스가 끝나면 새 앱을 여는 도우미를 띄운 뒤 화면에 끝내라고(`quit`) 알린다.
// 화면(Flutter)과는 main_get_common/main_set_common 의 `wald-update-*` 키로 주고받고(src/flutter_ffi.rs), 확인 결과는
// `wald_update_state` 이벤트로도 보낸다. 모두 화면 프로세스에서 돈다(토큰이 그 사용자의 LocalConfig 에 있다).
// 현장 수신 전용(결정 D44 — 부록 A-62): Windows 64·32비트(Sciter)·Android 도 이 모듈이다. 로그인하지 않으므로 받기 인증은
// 받기 키(src/wald_variant.rs field_update_key)다. Windows 설치본은 서비스가 띄운 SYSTEM `--server` 가 받아 UAC 없이 조용히
// 설치하고(`/WALDUPDATE=service`), 화면은 IPC(`Data::Config` 의 `wald-update-*` — src/ipc.rs)로 시작·상태만 주고받는다(relay).
// Android 는 받은 APK 를 화면이 Kotlin(WaldSelfUpdate.kt — 시스템 설치 창)에 넘긴다.
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

/// 받을 설치 파일 크기 상한(어드민이 주는 size·실제로 받은 양).
const MAX_SIZE: u64 = 300 * 1024 * 1024;
/// 서비스 설치(결정 D44)의 표식 — 다시 켜진 `--server` 가 트레이·메인 창을 되살리고 결과를 본다(on_server_start).
#[cfg(target_os = "windows")]
const PENDING: &str = "pending.json";

fn work_dir() -> PathBuf {
    // Android: 앱 데이터 폴더 — Kotlin(WaldSelfUpdate.kt)은 이 안의 파일만 설치한다.
    #[cfg(target_os = "android")]
    let dir = Some(hbb_common::config::APP_DIR.read().unwrap().clone())
        .filter(|d| !d.is_empty())
        .map(|d| PathBuf::from(d).join("wald-update"));
    // 서비스 설치: 설치 폴더(Program Files) 아래 — 일반 사용자는 읽기만 되어 SYSTEM 이 실행할 파일을 바꿔치기할 수 없다
    // (TEMP·ProgramData 는 쓰지 않는다).
    #[cfg(target_os = "windows")]
    let dir = if serves_relay() {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("update")))
    } else {
        None
    };
    #[cfg(target_os = "macos")]
    let dir: Option<PathBuf> = None;
    dir.unwrap_or_else(|| std::env::temp_dir().join("waldlust-update"))
}

/// 앱 안 업데이트를 하는 빌드: 데스크탑 양방향(D42)·현장 수신 전용 Windows·Android(D44). 발신 전용(폰)·Android 양방향은 아니다.
fn supported() -> bool {
    if cfg!(target_os = "android") {
        crate::wald_variant::is_incoming()
    } else {
        !crate::wald_variant::is_outgoing()
    }
}

/// 현장 Windows 설치본의 화면 프로세스(결정 D44): 받기·설치를 SYSTEM `--server` 에 맡기고 IPC 로 상태만 받는다.
#[cfg(target_os = "windows")]
fn relay() -> bool {
    static V: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *V.get_or_init(|| {
        crate::wald_variant::is_incoming()
            && !crate::platform::is_root()
            && crate::platform::is_installed()
    })
}

/// 현장 Windows 설치본의 서비스가 띄운 SYSTEM `--server`: 화면 대신 받고 조용히 설치한다.
#[cfg(target_os = "windows")]
fn serves_relay() -> bool {
    static V: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *V.get_or_init(|| {
        crate::wald_variant::is_incoming()
            && crate::platform::is_root()
            && crate::is_server()
            && crate::platform::is_cur_exe_the_installed()
    })
}

/// 화면이 고르는 안내 문구: service(현장 Windows — UAC 없음)·android(시스템 설치 창)·local(D42).
fn mode() -> &'static str {
    #[cfg(target_os = "windows")]
    if relay() || serves_relay() {
        return "service";
    }
    if cfg!(target_os = "android") {
        "android"
    } else {
        "local"
    }
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
    if !supported() {
        return;
    }
    #[cfg(target_os = "windows")]
    if relay() {
        return start_relay();
    }
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
    #[cfg(target_os = "windows")]
    if relay() {
        return relay_state();
    }
    let mut v = {
        let s = STATE.lock().unwrap();
        #[allow(unused_mut)]
        let mut v = serde_json::to_value(&*s).unwrap_or_default();
        // Android: 받은 APK — 화면이 Kotlin 설치에 넘긴다(WaldSelfUpdate.kt).
        #[cfg(target_os = "android")]
        if let Some(f) = &s.job.file {
            v["job"]["file"] = f.to_string_lossy().into();
        }
        v
    };
    v["current"] = crate::VERSION.into();
    v["mode"] = mode().into();
    if crate::wald_variant::is_incoming() {
        // 업데이트하면 끊길 원격 연결 수(확인 창). Windows 설치본은 이 값이 SYSTEM 서버에서 IPC 로 온다.
        v["conns"] = crate::Connection::alive_conns().len().into();
    }
    v.to_string()
}

/// 화면 → Rust(main_set_common): `wald-update-check`·`wald-update-start`(받기)·`wald-update-cancel`·`wald-update-install`,
/// `wald-update-fail`(Android 화면이 알린 설치 실패 — 값 = "코드:내용").
pub fn set_common(key: &str, value: &str) {
    #[cfg(target_os = "windows")]
    if relay() {
        return relay_command(key);
    }
    match key {
        "wald-update-check" => {
            std::thread::spawn(check);
        }
        "wald-update-start" => start_download(),
        "wald-update-cancel" => CANCEL.store(true, Ordering::SeqCst),
        "wald-update-install" => {
            std::thread::spawn(install);
        }
        "wald-update-fail" => fail_from_ui(value),
        _ => {}
    }
}

/// Android 화면이 알린 설치 결과(WaldSelfUpdate.kt — 확인 창 취소·기기 보안 차단·저장 공간·받은 파일 불일치·그 밖).
fn fail_from_ui(value: &str) {
    let (code, detail) = value.split_once(':').unwrap_or((value, ""));
    let code = match code {
        "aborted" => "aborted",
        "blocked" => "blocked",
        "space" => "space",
        "verify" => "verify",
        _ => "install",
    };
    LocalConfig::set_option("wald-update-target".to_owned(), String::new());
    fail(code, detail);
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
    if latest.size > MAX_SIZE {
        return fail("unavailable", format!("size {}", latest.size));
    }
    let token = if crate::wald_variant::is_incoming() {
        // 현장(결정 D44): 로그인하지 않는다 — 공통 비밀번호 해시에서 계산한 받기 키.
        match crate::wald_variant::field_update_key() {
            Some(key) => key,
            None => return fail("unavailable", "no field key"),
        }
    } else {
        let token = LocalConfig::get_option("access_token");
        if token.is_empty() {
            return fail("login", "");
        }
        token
    };
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
    // 디스크가 찼으면 space(Windows ERROR_DISK_FULL 112·ERROR_HANDLE_DISK_FULL 39, 그 밖 ENOSPC 28).
    let io = |e: std::io::Error| {
        let full = if cfg!(windows) {
            matches!(e.raw_os_error(), Some(112 | 39))
        } else {
            e.raw_os_error() == Some(28)
        };
        (if full { "space" } else { "network" }, e.to_string())
    };
    let dir = work_dir();
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(io)?;
    // 받은 파일과 설치(풀어 쓰기)할 자리가 있어야 한다(앱·OS 볼륨 — common.rs waldlust_disk_space).
    if let Some((_, free)) = crate::common::waldlust_disk_space() {
        if free < l.size.saturating_mul(3) + 200 * 1024 * 1024 {
            return Err(("space", format!("free {free} bytes")));
        }
    }
    let mut name: String = l
        .file_name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
        .collect();
    if name.trim_matches('.').is_empty() {
        name = format!("waldlust-update.{}", if cfg!(windows) { "exe" } else { "dmg" });
    }
    // 현장(결정 D44): Android 는 APK, 서비스 설치는 짧은 고정 이름(설치 명령 길이 — service_install).
    if cfg!(target_os = "android") {
        name = "update.apk".to_owned();
    }
    #[cfg(target_os = "windows")]
    if serves_relay() {
        name = "wald-update.exe".to_owned();
    }
    let path = dir.join(name);
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(30 * 60))
        // 인증 헤더를 다른 곳으로 따라 보내지 않는다(어드민 받기 경로는 넘겨주지 않는다).
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|e| net(&e))?;
    let mut req = client.get(&l.download).bearer_auth(token);
    if crate::wald_variant::is_incoming() {
        // 어드민 로그·기기별 받기 횟수 제한용(인증 아님).
        req = req.header("X-Wald-Device-Id", hbb_common::config::Config::get_id());
    }
    let mut resp = req.send().map_err(|e| net(&e))?;
    if crate::wald_variant::is_incoming()
        && matches!(
            resp.status(),
            reqwest::StatusCode::UNAUTHORIZED | reqwest::StatusCode::FORBIDDEN
        )
    {
        return Err(("key", resp.status().to_string()));
    }
    if resp.status() == reqwest::StatusCode::UNAUTHORIZED {
        return Err(("login", "401".to_owned()));
    }
    if !resp.status().is_success() {
        return Err(("network", resp.status().to_string()));
    }
    if let Some(n) = resp.content_length() {
        STATE.lock().unwrap().job.total = n;
    }
    let mut f = std::fs::File::create(&path).map_err(io)?;
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
        done += n as u64;
        // 게시된 크기보다 많이 오면 멈춘다(디스크를 채우지 않게).
        if done > MAX_SIZE || (l.size > 0 && done > l.size) {
            drop(f);
            let _ = std::fs::remove_file(&path);
            return Err(("hash", format!("more than {} bytes", l.size)));
        }
        f.write_all(&buf[..n]).map_err(io)?;
        hasher.update(&buf[..n]);
        STATE.lock().unwrap().job.done = done;
    }
    f.flush().map_err(io)?;
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
    if serves_relay() {
        return service_install(file);
    }
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

/// 현장 Windows 설치본(결정 D44): SYSTEM `--server` 가 받은 설치 파일을 UAC 없이 조용히 실행한다. 업스트림 자동 업데이트
/// (src/updater.rs)와 같은 launch_privileged_process — winlogon 토큰·DETACHED_PROCESS 라 설치 프로그램이 서비스와 이 프로세스를
/// 꺼도(PrepareToInstall) 남는다. `/WALDUPDATE=service` 는 D42 의 다시 띄우기 줄(runasoriginaluser — 여기서는 SYSTEM 이 된다)을
/// 건너뛴다. 다시 켜기는 새 `--server` 가 시작할 때 표식을 보고 한다(on_server_start).
#[cfg(target_os = "windows")]
fn service_install(file: &Path) -> Result<(), (&'static str, String)> {
    use winapi::um::{
        handleapi::CloseHandle, processthreadsapi::GetExitCodeProcess,
        synchapi::WaitForSingleObject,
    };
    const WAIT_TIMEOUT: u32 = 0x102;
    let install = |e: String| ("install", e);
    let session = crate::platform::get_current_process_session_id()
        .filter(|s| *s != 0)
        .ok_or_else(|| install("no user session".to_owned()))?;
    let dir = file.parent().ok_or_else(|| install("no folder".to_owned()))?;
    let log_file = dir.join("install.log");
    let cmd = format!(
        "\"{}\" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /WALDUPDATE=service /LOG=\"{}\"",
        file.display(),
        log_file.display()
    );
    // LaunchProcessWin 은 명령을 MAX_PATH(260) 버퍼에 복사한다(src/platform/windows.cc) — 넘으면 프로세스가 죽는다.
    let len = cmd.encode_utf16().count();
    if len >= 250 {
        return Err(install(format!("command too long ({len})")));
    }
    let marker = dir.join(PENDING);
    let version = STATE.lock().unwrap().job.version.clone();
    let pending = serde_json::json!({ "target": version, "at": get_time() });
    std::fs::write(&marker, pending.to_string()).map_err(|e| install(e.to_string()))?;
    let h = match crate::platform::launch_privileged_process(session, &cmd) {
        Ok(h) if !h.is_null() => h,
        r => {
            let _ = std::fs::remove_file(&marker);
            return Err(install(match r {
                Err(e) => e.to_string(),
                Ok(_) => std::io::Error::last_os_error().to_string(),
            }));
        }
    };
    log::info!("wald update: service installer started {}", file.display());
    let process = h as usize; // HANDLE 은 Send 가 아니다
    std::thread::spawn(move || {
        let h = process as winapi::um::winnt::HANDLE;
        let mut code = 0u32;
        let waited = unsafe { WaitForSingleObject(h, 15 * 60 * 1000) };
        unsafe {
            GetExitCodeProcess(h, &mut code);
            CloseHandle(h);
        }
        // 여기까지 왔으면 설치 프로그램이 이 서버를 끄지 않고 끝났다(또는 15분이 지났다).
        let _ = std::fs::remove_file(&marker);
        let timeout = if waited == WAIT_TIMEOUT { " timeout" } else { "" };
        fail("install", format!("exit {code}{timeout}, log {}", log_file.display()));
    });
    Ok(())
}

/// 서비스가 띄운 `--server` 가 시작할 때(src/core_main.rs): 현장 Windows 설치본이면 확인을 시작하고, 앱 안 업데이트(표식) 뒤라면
/// 트레이·메인 창을 로그인 사용자로 다시 띄운다(설치 프로그램이 껐다). 설치되지 않았으면(옛 서비스가 되살아남) 오류를 남긴다.
#[cfg(target_os = "windows")]
pub fn on_server_start() {
    if !serves_relay() {
        return;
    }
    std::thread::spawn(|| {
        // start() 가 작업 폴더를 비우기 전에 표식과 설치 로그 마지막 줄을 읽는다.
        let dir = work_dir();
        let marker = dir.join(PENDING);
        let pending = std::fs::read_to_string(&marker)
            .ok()
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
        let log_tail = std::fs::read(dir.join("install.log"))
            .map(|b| String::from_utf8_lossy(&b).into_owned())
            .ok()
            .and_then(|s| {
                s.lines()
                    .rev()
                    .find(|l| !l.trim().is_empty())
                    .map(str::to_owned)
            })
            .unwrap_or_default();
        let _ = std::fs::remove_file(&marker);
        start();
        let Some(p) = pending else {
            return;
        };
        if get_time() - p["at"].as_i64().unwrap_or_default() > 15 * 60 * 1000 {
            return;
        }
        let target = p["target"].as_str().unwrap_or_default();
        if get_version_number(crate::VERSION) < get_version_number(target) {
            fail("install", format!("still {} after {target}: {log_tail}", crate::VERSION));
        } else {
            log::info!("wald update: updated to {}", crate::VERSION);
        }
        relaunch_ui();
    });
}

/// 설치 프로그램이 끈 트레이와 메인 창을 이 세션의 로그인 사용자로 띄운다(업스트림 update_me 의 트레이 되살리기와 같은 방식).
#[cfg(target_os = "windows")]
fn relaunch_ui() {
    // 화면이 먼저 뜨면 IPC 서버를 차지해 이 서버가 그 화면을 끈다(src/server.rs) — 이 서버의 IPC 가 답할 때까지 기다린다.
    for _ in 0..60 {
        if matches!(crate::ipc::get_config("id"), Ok(Some(_))) {
            break;
        }
        std::thread::sleep(Duration::from_secs(1));
    }
    let (Ok(exe), Some(session)) = (
        std::env::current_exe(),
        crate::platform::get_current_process_session_id(),
    ) else {
        return;
    };
    let exe = exe.to_string_lossy().to_string();
    for args in [vec!["--tray"], vec![]] {
        // 로그인 직후라 explorer 가 아직 없으면 조금 뒤 다시 한다.
        for _ in 0..30 {
            match crate::platform::run_exe_in_session(&exe, args.clone(), session, true) {
                Ok(_) => break,
                Err(e) => {
                    log::warn!("wald update: relaunch {args:?}: {e}");
                    std::thread::sleep(Duration::from_secs(2));
                }
            }
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

/// IPC(src/ipc.rs — 서비스 `--server` 쪽): 현장 Windows 설치본의 화면이 묻는 상태. 이 서버가 맡지 않으면 None(옛 서버와 같다).
#[cfg(target_os = "windows")]
pub fn ipc_get(name: &str) -> Option<String> {
    if !serves_relay() {
        return None;
    }
    start();
    Some(get_common(name)).filter(|s| !s.is_empty())
}

/// IPC: 화면의 확인·받기·취소·설치. URL·경로·해시는 받지 않는다 — 이 서버가 어드민에 다시 묻는다.
#[cfg(target_os = "windows")]
pub fn ipc_set(name: &str) {
    if serves_relay()
        && matches!(
            name,
            "wald-update-check" | "wald-update-start" | "wald-update-cancel" | "wald-update-install"
        )
    {
        set_common(name, "");
    }
}

#[cfg(target_os = "windows")]
lazy_static::lazy_static! {
    /// 화면 쪽 중계(relay): SYSTEM 서버에서 받은 마지막 상태 JSON.
    static ref RELAY: Mutex<String> = Default::default();
}
#[cfg(target_os = "windows")]
static RELAY_POKE: AtomicBool = AtomicBool::new(false);

/// 화면 쪽 중계: 서버 상태를 받는 중에는 1초, 쉴 때는 5초마다 읽고, 바뀌면 화면에 `wald_update_state` 를 보낸다.
#[cfg(target_os = "windows")]
fn start_relay() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        std::thread::spawn(|| loop {
            relay_poll();
            let state = relay_value()["job"]["state"]
                .as_str()
                .unwrap_or_default()
                .to_owned();
            let ticks = match state.as_str() {
                "downloading" | "verifying" | "ready" | "installing" => 4,
                _ => 20,
            };
            for _ in 0..ticks {
                if RELAY_POKE.swap(false, Ordering::SeqCst) {
                    break;
                }
                std::thread::sleep(Duration::from_millis(250));
            }
        });
    });
}

#[cfg(target_os = "windows")]
fn relay_value() -> serde_json::Value {
    serde_json::from_str(&RELAY.lock().unwrap()).unwrap_or_default()
}

#[cfg(target_os = "windows")]
fn relay_poll() {
    let new = match crate::ipc::get_config("wald-update-state") {
        Ok(Some(s)) => s,
        // 서비스가 꺼졌거나(트레이 '종료' 뒤 등) 이 기능이 없는 옛 서버다. 설치 중이면 설치 프로그램이 서비스를 끈 것이라 그대로 둔다.
        r => {
            let mut v = relay_value();
            if v["job"]["state"] == "installing" {
                return;
            }
            v["status"] = "error".into();
            v["error"] = match r {
                Err(e) => e.to_string(),
                Ok(_) => "no answer".to_owned(),
            }
            .into();
            v["current"] = crate::VERSION.into();
            v["mode"] = "service".into();
            v.to_string()
        }
    };
    let changed = {
        let mut s = RELAY.lock().unwrap();
        let changed = *s != new;
        if changed {
            *s = new.clone();
        }
        changed
    };
    #[cfg(feature = "flutter")]
    if changed {
        let mut v: serde_json::Value = serde_json::from_str(&new).unwrap_or_default();
        v["name"] = "wald_update_state".into();
        let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, v.to_string());
    }
    #[cfg(not(feature = "flutter"))]
    let _ = changed;
}

#[cfg(target_os = "windows")]
fn relay_state() -> String {
    let s = RELAY.lock().unwrap().clone();
    if !s.is_empty() {
        return s;
    }
    serde_json::json!({ "status": "checking", "current": crate::VERSION, "mode": "service", "job": { "state": "idle" } })
        .to_string()
}

/// 화면의 명령을 SYSTEM 서버로 보낸다. 화면이 곧바로 진행 상태를 보도록 캐시를 먼저 바꾼다(실제 상태는 다음 폴링에서 온다).
#[cfg(target_os = "windows")]
fn relay_command(key: &str) {
    if !matches!(
        key,
        "wald-update-check" | "wald-update-start" | "wald-update-cancel" | "wald-update-install"
    ) {
        return;
    }
    {
        let mut v = relay_value();
        match key {
            "wald-update-check" => v["status"] = "checking".into(),
            "wald-update-start" => {
                v["job"] = serde_json::json!({
                    "state": "downloading",
                    "version": v["latest"]["version"].clone(),
                    "total": v["latest"]["size"].clone(),
                    "done": 0,
                });
            }
            "wald-update-install" => {
                v["job"]["state"] = "installing".into();
                // 다시 켜진 화면이 업데이트됐는지 본다(flutter/lib/common.dart checkUpdate — D42 와 같은 로컬 옵션).
                if let Some(version) = v["job"]["version"].as_str() {
                    LocalConfig::set_option("wald-update-target".to_owned(), version.to_owned());
                }
            }
            _ => {}
        }
        *RELAY.lock().unwrap() = v.to_string();
    }
    let key = key.to_owned();
    std::thread::spawn(move || {
        if let Err(e) = crate::ipc::set_config(&key, String::new()) {
            log::warn!("wald update relay {key}: {e}");
            let mut v = relay_value();
            v["job"] = serde_json::json!({ "state": "error", "error": "service", "detail": e.to_string() });
            *RELAY.lock().unwrap() = v.to_string();
        }
        RELAY_POKE.store(true, Ordering::SeqCst);
    });
}

/// Android: 설치는 화면이 Kotlin(WaldSelfUpdate.kt — 시스템 설치 창)에 맡긴다. 여기서는 `installing` 상태만 남는다.
#[cfg(target_os = "android")]
fn platform_install(_file: &Path) -> Result<(), (&'static str, String)> {
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
