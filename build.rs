#[cfg(windows)]
fn build_windows() {
    let file = "src/platform/windows.cc";
    let file2 = "src/platform/windows_delete_test_cert.cc";
    cc::Build::new().file(file).file(file2).compile("windows");
    println!("cargo:rustc-link-lib=WtsApi32");
    println!("cargo:rerun-if-changed={}", file);
    println!("cargo:rerun-if-changed={}", file2);
}

#[cfg(target_os = "macos")]
fn build_mac() {
    let file = "src/platform/macos.mm";
    let mut b = cc::Build::new();
    if let Ok(os_version::OsVersion::MacOS(v)) = os_version::detect() {
        let v = v.version;
        if v.contains("10.14") {
            b.flag("-DNO_InputMonitoringAuthStatus=1");
        }
    }
    b.flag("-std=c++17").file(file).compile("macos");
    println!("cargo:rerun-if-changed={}", file);
}

#[cfg(all(windows, feature = "inline"))]
fn build_manifest() {
    use std::io::Write;
    if std::env::var("PROFILE").unwrap() == "release" {
        let mut res = winres::WindowsResource::new();
        res.set_icon("res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("res/manifest.xml");
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}

fn install_android_deps() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os != "android" {
        return;
    }
    let mut target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_arch == "x86_64" {
        target_arch = "x64".to_owned();
    } else if target_arch == "x86" {
        target_arch = "x86".to_owned();
    } else if target_arch == "aarch64" {
        target_arch = "arm64".to_owned();
    } else {
        target_arch = "arm".to_owned();
    }
    let target = format!("{}-android", target_arch);
    let vcpkg_root = std::env::var("VCPKG_ROOT").unwrap();
    let mut path: std::path::PathBuf = vcpkg_root.into();
    if let Ok(vcpkg_root) = std::env::var("VCPKG_INSTALLED_ROOT") {
        path = vcpkg_root.into();
    } else {
        path.push("installed");
    }
    path.push(target);
    println!(
        "cargo:rustc-link-search={}",
        path.join("lib").to_str().unwrap()
    );
    println!("cargo:rustc-link-lib=ndk_compat");
    println!("cargo:rustc-link-lib=oboe");
    println!("cargo:rustc-link-lib=c++");
    println!("cargo:rustc-link-lib=OpenSLES");
}

// Waldlust(DSK-01): 빌드 변형을 확인한다. 수신 전용 빌드는 공통 영구 비밀번호 해시가 없으면 멈춘다
// (src/wald_variant.rs, res/wald-variant/preset_hash.py). 값은 출력하지 않는다.
fn check_waldlust_variant() {
    for key in [
        "WALDLUST_VARIANT",
        "WALDLUST_INCOMING_PW_STORAGE",
        "WALDLUST_INCOMING_PW_SALT",
    ] {
        println!("cargo:rerun-if-env-changed={}", key);
    }
    match std::env::var("WALDLUST_VARIANT").unwrap_or_default().as_str() {
        // DSK-12: 발신 전용(직원 폰)은 비밀번호 해시·아이콘을 넣지 않는다.
        "" | "bidirectional" | "outgoing" => return,
        "incoming" => {}
        _ => panic!("WALDLUST_VARIANT 는 비우거나 bidirectional·incoming·outgoing 이어야 한다"),
    }
    let storage = std::env::var("WALDLUST_INCOMING_PW_STORAGE").unwrap_or_default();
    let salt = std::env::var("WALDLUST_INCOMING_PW_SALT").unwrap_or_default();
    // "00" + base64(SHA-256) 44자(끝은 '=')
    let storage_ok = storage.len() == 46
        && storage.starts_with("00")
        && storage.ends_with('=')
        && storage[2..]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/' || b == b'=');
    let salt_ok = salt.len() >= 16
        && salt
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    if !storage_ok || !salt_ok {
        panic!(
            "수신 전용 빌드(WALDLUST_VARIANT=incoming)에는 공통 영구 비밀번호 해시가 필요하다: \
             res/wald-variant/preset_hash.py 로 WALDLUST_INCOMING_PW_STORAGE·WALDLUST_INCOMING_PW_SALT 를 만든다"
        );
    }
    check_incoming_icons();
}

// Waldlust(DSK-10): 수신 전용 빌드는 res/wald-variant/apply_icons.py 로 ↓ 배지 아이콘을 덮어쓴 뒤 빌드한다.
// 빠뜨리면 양방향 아이콘이 들어가므로 멈춘다(cargo 빌드가 Flutter 빌드보다 먼저 돈다). 덮어쓴 대상 파일은
// Rust 결과에 영향이 없어 rerun-if-changed 로 감시하지 않는다 — 수정 시각만 바뀌어도 librustdesk 를 통째로 다시
// 빌드하게 된다. 새 체크아웃·변형 전환(환경변수)·묶음 변경 때 이 검사가 다시 돈다.
fn check_incoming_icons() {
    let src = std::path::Path::new("res/wald-variant/incoming-icons");
    let mut dirs = vec![src.to_path_buf()];
    let mut count = 0;
    while let Some(dir) = dirs.pop() {
        let entries = std::fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("{} 를 읽지 못했다: {}", dir.display(), e));
        for entry in entries {
            let path = entry
                .unwrap_or_else(|e| panic!("{} 를 읽지 못했다: {}", dir.display(), e))
                .path();
            if path.is_dir() {
                dirs.push(path);
                continue;
            }
            if path
                .file_name()
                .map_or(true, |n| n.to_string_lossy().starts_with('.'))
            {
                continue;
            }
            let Ok(dst) = path.strip_prefix(src) else {
                continue;
            };
            println!("cargo:rerun-if-changed={}", path.display());
            if std::fs::read(&path).ok() != std::fs::read(dst).ok() {
                panic!(
                    "수신 전용 빌드인데 {} 가 수신 전용 아이콘이 아니다: \
                     빌드 전에 python3 res/wald-variant/apply_icons.py 를 실행한다",
                    dst.display()
                );
            }
            count += 1;
        }
    }
    if count == 0 {
        panic!("수신 전용 아이콘(res/wald-variant/incoming-icons)이 없다");
    }
}

fn main() {
    check_waldlust_variant();
    hbb_common::gen_version();
    install_android_deps();
    #[cfg(all(windows, feature = "inline"))]
    build_manifest();
    // Waldlust(DSK-12): 빌드 스크립트의 cfg 는 호스트 기준이라 Windows 에서 Android 를 빌드하면 Windows 코드가 섞인다.
    #[cfg(windows)]
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        build_windows();
    }
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os == "macos" {
        #[cfg(target_os = "macos")]
        build_mac();
        println!("cargo:rustc-link-lib=framework=ApplicationServices");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
