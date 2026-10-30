//! Waldlust: 빌드 변형 — 양방향(기본) / 수신 전용(DSK-01·DSK-02) / 발신 전용(DSK-12).
//!
//! 빌드 환경변수 `WALDLUST_VARIANT=incoming` 으로 만든 수신 전용 빌드는 프로세스가 시작할 때
//! `res/wald-variant/incoming.json` 의 프리셋(발신 차단·설정 잠금·원격 기능 제한·수락 방식)과
//! 빌드 때 넣은 공통 영구 비밀번호 해시(`WALDLUST_INCOMING_PW_STORAGE`·`WALDLUST_INCOMING_PW_SALT`,
//! 평문 아님 — res/wald-variant/preset_hash.py 로 만든다)를 설정 맵에 넣는다. 값은 custom.txt 와
//! 같은 형식이라 업스트림 분배 로직(`apply_custom_client_config`)이 키마다 맞는 맵에 넣는다.
//! `WALDLUST_VARIANT=outgoing`(직원 폰)은 `res/wald-variant/outgoing.json`(conn-type outgoing — 업스트림
//! `is_outgoing_only()` 가 hbbs 등록·화면 공유를 끈다)만 넣는다. heartbeat 는 그대로 보낸다(폰 ID 확인용).
//! 모든 변형이 `res/wald-variant/common.json` 의 공통 프리셋을 먼저 넣는다(DSK-11 — Android 플로팅 창을
//! 투명·터치 통과로). 양방향 빌드는 그 밖에 아무것도 하지 않는다. 환경변수 값 검사는 build.rs 가 한다.

use hbb_common::{
    config::{Config, LocalConfig},
    log, ResultType,
};
use std::collections::HashMap;

const VARIANT: Option<&str> = option_env!("WALDLUST_VARIANT");
const INCOMING_PW_STORAGE: Option<&str> = option_env!("WALDLUST_INCOMING_PW_STORAGE");
const INCOMING_PW_SALT: Option<&str> = option_env!("WALDLUST_INCOMING_PW_SALT");
const INCOMING_PRESET: &str = include_str!("../res/wald-variant/incoming.json");
const COMMON_PRESET: &str = include_str!("../res/wald-variant/common.json");
const OUTGOING_PRESET: &str = include_str!("../res/wald-variant/outgoing.json");
// 현장 앱 안 업데이트(D44)의 받기 키 라벨. preset_hash.py --field-key-sha256 과 같아야 한다.
const FIELD_KEY_LABEL: &str = "waldlust-field-update-v1:";

#[inline]
pub fn is_incoming() -> bool {
    matches!(VARIANT, Some("incoming"))
}

#[inline]
pub fn is_outgoing() -> bool {
    matches!(VARIANT, Some("outgoing"))
}

/// heartbeat 로 보고하는 변형 이름.
pub fn name() -> &'static str {
    if is_incoming() {
        "incoming"
    } else if is_outgoing() {
        "outgoing"
    } else {
        "bidirectional"
    }
}

/// 공통 프리셋을, 수신 전용·발신 전용 빌드면 그 프리셋도 적용한다. 프로세스마다 설정 파일을 쓰기 전에 불러야 한다
/// (데스크탑 `global_init()` 첫머리, Android 는 APP_DIR 이 정해진 직후). 여러 번 불러도 한 번만 적용한다.
pub fn apply() {
    apply_common();
    if is_outgoing() {
        apply_outgoing();
        return;
    }
    if !is_incoming() {
        return;
    }
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        // 로컬 영구 비밀번호가 있으면 사전 비밀번호보다 우선한다(server/connection.rs validate_password).
        // 관리 빌드 위에 덮어 설치한 기기의 기기별 비밀번호를 지워 공통 비밀번호만 통하게 한다.
        // 변경 금지 플래그(disable-change-permanent-password)를 넣기 전에 해야 한다.
        // Windows 설치형은 서비스(SYSTEM)만 지우고, 사용자 쪽은 서비스→사용자 동기화로 따라온다.
        if crate::common::waldlust_owns_password() {
            let (local_storage, _) = Config::get_local_permanent_password_storage_and_salt();
            if !local_storage.is_empty() && !Config::set_permanent_password("") {
                log::error!("Failed to clear the local permanent password");
            }
            if !LocalConfig::get_option(crate::common::WALDLUST_MANAGED_PW_KEY).is_empty() {
                LocalConfig::set_option(
                    crate::common::WALDLUST_MANAGED_PW_KEY.to_owned(),
                    String::new(),
                );
            }
        }
        match incoming_preset(
            INCOMING_PW_STORAGE.unwrap_or_default(),
            INCOMING_PW_SALT.unwrap_or_default(),
        ) {
            Ok(data) => crate::common::apply_custom_client_config(data),
            Err(e) => log::error!("Failed to parse the incoming-only preset: {}", e),
        }
    });
}

/// 두 변형 공통 프리셋(DSK-11): Android 플로팅 창(화면 가장자리 버블)을 투명·터치 통과로 만든다.
/// 창 자체는 남아 '원격 제어 중 화면 켜짐 유지'와 백그라운드 서비스 유지를 계속 맡는다.
fn apply_common() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| match serde_json::from_str(COMMON_PRESET) {
        Ok(data) => crate::common::apply_custom_client_config(data),
        Err(e) => log::error!("Failed to parse the common preset: {}", e),
    });
}

/// 발신 전용 프리셋(DSK-12): 직원 개인 폰은 원격을 받지 않는다.
fn apply_outgoing() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| match serde_json::from_str(OUTGOING_PRESET) {
        Ok(data) => crate::common::apply_custom_client_config(data),
        Err(e) => log::error!("Failed to parse the outgoing-only preset: {}", e),
    });
}

/// 현장 앱 안 업데이트(DSK-01, 결정 D44)의 받기 키. 수신 전용은 로그인하지 않으므로 빌드에 든 공통 비밀번호
/// 해시에서 계산한다 — 새 비밀을 더하지 않는다(키를 꺼낼 수 있는 사람은 이미 설치본, 곧 해시를 가졌다).
/// 어드민은 이 값의 SHA-256 만 둔다(preset_hash.py --field-key-sha256). 로그·상태·IPC·heartbeat 에 넣지 않는다.
pub(crate) fn field_update_key() -> Option<String> {
    if !is_incoming() {
        return None;
    }
    field_key_of(INCOMING_PW_STORAGE.unwrap_or_default())
}

fn field_key_of(pw_storage: &str) -> Option<String> {
    use hbb_common::sha2::{Digest, Sha256};
    if pw_storage.is_empty() {
        return None;
    }
    let mut hasher = Sha256::new();
    hasher.update(FIELD_KEY_LABEL.as_bytes());
    hasher.update(pw_storage.as_bytes());
    Some(hex::encode(hasher.finalize()))
}

fn incoming_preset(
    pw_storage: &str,
    pw_salt: &str,
) -> ResultType<HashMap<String, serde_json::Value>> {
    let mut data: HashMap<String, serde_json::Value> = serde_json::from_str(INCOMING_PRESET)?;
    // 사전 비밀번호(HARD password·salt): 로컬 영구 비밀번호가 비어 있을 때 인증에 쓰인다.
    data.insert("password".to_owned(), pw_storage.into());
    data.insert("salt".to_owned(), pw_salt.into());
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        config::{self, keys},
        sodiumoxide::base64,
    };

    // 테스트 벡터(실제 비밀번호 아님). 기대값은 res/wald-variant/preset_hash.py 에 같은 입력을 넣은 출력이다.
    const TEST_PASSWORD: &str = "test-vector-not-a-secret";
    const TEST_SALT: &str = "test-vector-salt-0001";
    const TEST_STORAGE: &str = "00I3okxVCwTJpCmMix2hsBSglaBS+9MUETMw8qyn2wl8E=";

    #[test]
    fn test_preset_hash_matches_helper() {
        let h1 = config::compute_permanent_password_h1(TEST_PASSWORD, TEST_SALT);
        let storage = format!("00{}", base64::encode(h1, base64::Variant::Original));
        assert_eq!(storage, TEST_STORAGE);
        assert!(config::decode_preset_password_h1_from_storage(TEST_STORAGE).is_some());
        assert!(config::preset_permanent_password_storage_is_usable_for_auth(
            TEST_STORAGE,
            TEST_SALT
        ));
    }

    // 받기 키(D44): 기대값은 preset_hash.py 와 같은 계산(라벨 + 저장 해시의 SHA-256 hex)이다.
    #[test]
    fn test_field_key_vector() {
        assert_eq!(
            field_key_of(TEST_STORAGE).as_deref(),
            Some("751870313a9d1a70c160f8bc4112a15010ea29fb92d504fb513eba3886f73219")
        );
        assert_eq!(field_key_of(""), None);
    }

    // 프리셋 키가 의도한 맵(HARD·BUILTIN·OVERWRITE·OVERWRITE_LOCAL)에 들어가는지 본다.
    // 설정 파일에는 쓰지 않는다(맵과 읽기만).
    #[test]
    fn test_incoming_preset_maps() {
        let data = incoming_preset(TEST_STORAGE, TEST_SALT).unwrap();
        crate::common::apply_custom_client_config(data);

        // HARD
        assert!(config::is_incoming_only());
        assert!(config::is_disable_settings());
        assert!(config::is_disable_account());
        assert!(config::is_disable_ab());
        assert_eq!(
            Config::get_preset_password_storage_and_salt(),
            (TEST_STORAGE.to_owned(), TEST_SALT.to_owned())
        );
        // BUILTIN
        assert!(Config::is_disable_change_permanent_password());
        assert!(Config::is_disable_change_id());
        assert_eq!(
            crate::common::get_builtin_option(keys::OPTION_HIDE_STOP_SERVICE),
            "Y"
        );
        // D35(부록 A-25): 'RustDesk 기반 · 오픈소스 고지' 링크는 수신 전용에도 보인다(A-19 의 숨김을 바꿈 —
        // 원저작물 표기·소스 위치·제3자 고지).
        assert_ne!(
            crate::common::get_builtin_option(keys::OPTION_HIDE_POWERED_BY_ME),
            "Y"
        );
        // OVERWRITE
        for (k, v) in [
            (keys::OPTION_VERIFICATION_METHOD, "use-both-passwords"),
            (keys::OPTION_APPROVE_MODE, "password"),
            (keys::OPTION_ALLOW_AUTO_UPDATE, "N"),
            (keys::OPTION_ENABLE_TERMINAL, "N"),
            (keys::OPTION_ENABLE_TUNNEL, "N"),
            (keys::OPTION_ENABLE_REMOTE_PRINTER, "N"),
            (keys::OPTION_ENABLE_CAMERA, "N"),
            (keys::OPTION_ENABLE_FILE_TRANSFER, "Y"),
            (keys::OPTION_ACCESS_MODE, "custom"),
            ("allow-hide-cm", "N"),
        ] {
            assert_eq!(Config::get_option(k), v, "{k}");
        }
        // OVERWRITE_LOCAL(Android Kotlin 은 LocalConfig 로 읽는다)
        assert_eq!(LocalConfig::get_option("allow-hide-cm"), "N");
        // 변경 금지: 영구 비밀번호를 바꾸려 해도 거부한다.
        assert!(!Config::set_permanent_password("changed-by-user"));
    }

    // 공통 프리셋(DSK-11): 플로팅 창 값이 OVERWRITE_LOCAL 에 들어간다(Android Kotlin 은 LocalConfig 로 읽는다).
    #[test]
    fn test_common_preset_maps() {
        apply_common();
        for (k, v) in [
            (keys::OPTION_FLOATING_WINDOW_TRANSPARENCY, "0"),
            (keys::OPTION_FLOATING_WINDOW_UNTOUCHABLE, "Y"),
        ] {
            assert_eq!(LocalConfig::get_option(k), v, "{k}");
        }
    }

    // 발신 전용 프리셋(DSK-12)은 conn-type 하나뿐이다. 맵에 넣으면 test_incoming_preset_maps 와 HARD 맵의
    // conn-type 을 두고 병렬로 다투므로 JSON 만 본다.
    #[test]
    fn test_outgoing_preset() {
        let data: HashMap<String, serde_json::Value> =
            serde_json::from_str(OUTGOING_PRESET).unwrap();
        assert_eq!(data.len(), 1);
        assert_eq!(
            data.get("conn-type").and_then(|v| v.as_str()),
            Some("outgoing")
        );
    }
}
