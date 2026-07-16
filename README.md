# Build Automation (com.actionfit.buildautomation)

ActionFit Unity 프로젝트에서 BuildCommit 기반 자동 빌드 요청과 macOS self-hosted GitHub Actions 모바일 빌드를 관리하는 에디터 패키지입니다.

이 패키지는 `com.actionfit.buildsetting`의 빌드 설정과 `com.actionfit.customsymbols`의 build 체크 심볼을 사용합니다. Build Automation은 빌드 메타데이터와 프로젝트별 Android keystore Base64 및 signing 비밀번호를 BuildRequest에 저장합니다. Google Play, iOS, App Store Connect, certificate, keychain, Slack credential은 신뢰된 Unity self-hosted runner가 공유 `CI_SECRET_ROOT`에서 읽습니다.

## 설치

```json
{
  "dependencies": {
    "com.actionfit.buildsetting": "https://github.com/ActionFit-Editor/Build_Setting.git#1.1.11",
    "com.actionfit.githubauth": "https://github.com/ActionFit-Editor/AI_GitHub.git#1.0.8",
    "com.actionfit.customsymbols": "https://github.com/ActionFit-Editor/Custom_Symbols.git#1.0.7",
    "com.actionfit.buildautomation": "https://github.com/ActionFit-Editor/Build_Automation.git#1.0.56"
  }
}
```

`Build_Automation` 또는 `AI_GitHub` 레포와 태그가 아직 배포되지 않았다면 위 URL은 배포 후 사용할 수 있습니다.

## Agent Skills

Custom Package Manager의 `Install or Refresh Agent Skills`는 Codex와 Claude에 다음 read-only skill을 설치합니다.

- `mobile-build-help`: BuildCommit, workflow, runner 구조와 build request 경계를 설명합니다.
- `mobile-build-preflight`: 패키지 의존성, Unity 프로젝트 경로, workflow 동기화 상태, 안전한 BuildRequest 필드와 GitHub 준비 상태를 변경 없이 점검합니다.

preflight는 signing 값, keystore Base64, token, webhook, certificate와 keychain 내용을 읽거나 출력하지 않습니다. BuildRequest 생성, workflow sync, settings 변경, commit/tag/push, Unity build, upload와 deploy도 수행하지 않습니다.

## Unity Menu

- Package root: `Tools > Package > Build Automation`.
- README: `Tools > Package > Build Automation > README`.
- Setting SO: `Tools > Package > Build Automation > Setting SO`.
- Package commands stay under the same package root and appear above the separated README/Setting SO entries when those entries exist.

## 구성

- 메뉴: `Tools > Package > Build Automation > AutoBuild`
- 요청 파일: Git 저장소 루트 `.build/build_request.json`
- CI 빌드 진입점: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`
- CI 타겟 전환 진입점: `ActionFit.BuildAutomation.Editor.CIBuildEntry.SwitchToRequestBuildTarget`
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`
- Build script sources: `.github/scripts/resolve-unity-project.sh`, `.github/scripts/resolve-unity-editor.sh`, `.github/scripts/resolve-local-secret-root.sh`, `.github/scripts/validate-local-runner-secrets.sh`, `.github/scripts/prepare-actionfit-private-package-access.sh`, `.github/scripts/notify-slack-build-result.sh`, `.github/scripts/upload-slack-file.sh`, `.github/scripts/check-testflight-build-number.rb`, `.github/scripts/cleanup-old-build-artifacts.sh`
- Workflow sync: `AutoBuild` 창의 `Update GitHub Workflow` 버튼
- 자동 빌드 설정 에셋: `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`
- Mac runner guide: `MAC_SELF_HOSTED_RUNNER_SETUP.md`

## AutoBuild

`AutoBuild` 창은 연결된 `BuildSettingsSO`의 버전과 번들 번호를 `PlayerSettings`에 적용한 뒤 Git 저장소 루트의 `.build/build_request.json`을 생성합니다. Unity 프로젝트가 저장소 루트에 있으면 `unityProjectPath`는 `.`, `KnitFactory/Assets`처럼 nested 구조이면 `KnitFactory`가 됩니다. 그 다음 `[BuildRequest] v{version}({bundleNo})` 형식의 저장용 커밋을 만들고 push한 뒤, `build/{platform}-{upload}/{version}/{bundleNo}-{shortSha}` 형식의 태그를 생성해 push합니다. `BuildSettingsSO`가 없으면 Build Setting 패키지가 Unity 프로젝트의 `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 자동 생성하고 `PlayerSettings` 기본값을 1차 초기화합니다.

`Commit, Tag & Push`는 Unity를 실행 중인 로컬 기기의 `git push`와 tag push 권한을 사용합니다. 자동빌드를 요청하는 각 개발자 기기는 해당 GitHub repository에 push/tag 권한이 있는 계정으로 Git 인증을 먼저 설정해야 합니다. BuildCommit은 커밋 생성 전에 `com.actionfit.githubauth`의 preflight를 reflection으로 호출하고, 인증이 없으면 GitHub 인증 필요 팝업을 띄운 뒤 중단합니다. `com.actionfit.buildsetting`, `com.actionfit.customsymbols` 또는 `com.actionfit.githubauth`가 누락된 프로젝트에서는 필요한 기능을 막고 의존성 설치를 안내합니다. ActionFit Package Manager로 설치/업데이트하면 catalog CSV의 dependency 정보가 Unity 프로젝트의 `Packages/manifest.json`에 Git UPM URL로 함께 기록됩니다. 수동으로 manifest를 편집하는 경우에는 Build Automation, Build Setting, Custom Symbols, AI GitHub Git UPM URL을 직접 추가해야 합니다. 자세한 GitHub 연결 확인 순서와 오류별 안내는 `Packages/com.actionfit.githubauth/README.md`를 확인합니다.

BuildCommit의 Git 명령은 stdout과 stderr를 동시에 읽어 `core.autocrlf=true` 환경에서 대량 줄바꿈 경고가 발생해도 파이프가 막히지 않도록 합니다. 각 명령은 최대 5분 동안 실행되며, timeout이면 프로세스 트리를 종료하고 오류를 기록합니다. 다른 Git 작업이 `.git/index.lock`을 잠시 점유하면 250ms 간격으로 최대 20회 재시도하고, 계속 점유 중이면 기존 오류를 표시한 채 중단합니다. 실행 중인 Git 프로세스의 lock을 직접 삭제하지 않습니다.

`CS0103: The name 'BuildSettingBridge' does not exist in the current context`가 발생하면 `com.actionfit.buildautomation`을 `1.0.25` 이상으로 업데이트한 뒤 `AssetDatabase.Refresh` 또는 Unity 재시작으로 스크립트 컴파일 목록을 갱신합니다. 이 버전부터 bridge 타입은 Unity가 이미 컴파일하는 소스에 포함되어 부분 refresh 상태에서도 BuildAutomation 참조가 깨지지 않도록 되어 있습니다.

`Auto Sync Build Files`는 기본값이 켜짐입니다. 켜져 있으면 `Commit, Tag & Push` 실행 시 Build Automation 패키지의 workflow, composite actions, scripts를 Git 저장소 루트 `.github/`로 먼저 동기화하고, 그 변경분도 같은 저장 커밋에 포함합니다. GitHub 제약상 workflow 위치는 항상 저장소 루트 `.github/workflows`이고 Unity 프로젝트가 nested인지와 무관합니다.

`AutoBuild` 창 본문은 세로 스크롤 영역입니다. 창 높이가 낮아져도 Version Info, CI Build Request, GitHub Workflow, 버튼, Log 순서가 유지되며 Log 영역은 별도 스크롤을 사용합니다.

실제 GitHub Actions 빌드 요청은 저장 커밋 push가 아니라 `build/**` 태그 push로 발생합니다. 저장 커밋은 요청 JSON과 변경사항을 남기는 용도이며, 같은 버전으로 재요청할 수 있도록 커밋은 `--allow-empty`를 허용합니다.

Android/iOS Unity batchmode 빌드가 실패하면 workflow가 `$UNITY_PROJECT_DIR/Logs/unity-android.log` 또는 `$UNITY_PROJECT_DIR/Logs/unity-ios.log` 마지막 400줄을 GitHub Actions log group에 출력합니다. 따라서 실패 원인 확인을 위해 먼저 artifact를 내려받지 않아도 됩니다.

`Platform` 기본값은 `None`이며, 플랫폼을 선택하지 않으면 `Commit, Tag & Push` 버튼이 비활성화됩니다. `Current`, Android, iOS, Both 중 하나를 명시적으로 선택해야 BuildCommit request를 만들 수 있습니다. `Current`를 직접 선택한 경우에는 Unity의 현재 active build target을 기준으로 Android 또는 iOS 요청으로 해석됩니다.

`Platform` 선택 시 `Build Kind`와 `Upload Target`은 자동 기본값으로 맞춰집니다. Android는 `AndroidAab`와 `GooglePlayInternal`, iOS는 `iOSXcodeProject`와 `TestFlight`, Both는 `Android AAB + iOS Xcode Project`와 `GooglePlayInternalAndTestFlight`를 사용합니다.

Android 요청에는 `androidKeystoreFileName`, `androidKeystoreBase64`, `androidKeystorePassword`, `androidAliasPassword`, `androidKeyaliasName`을 저장합니다. Android 빌드는 request의 keystore Base64와 두 비밀번호를 우선 사용하고, 해당 값이 비어 있을 때만 runner의 `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_PASS`를 fallback으로 사용합니다. Google Play JSON, iOS team credential, App Store Connect API key, certificate와 keychain 비밀번호는 runner 로컬 secret bundle에서 읽습니다.

Android package name은 `BuildSettingsSO.androidPackageName`, iOS bundle id는 `BuildSettingsSO.iosPackageName` 값을 request에 함께 저장합니다. workflow는 이 request 값을 Google Play `packageName`과 TestFlight `app_identifier`로 사용하므로, profile별 package/bundle id를 workflow env에 따로 적지 않습니다.

`Distribution Profile`은 배포 계정 선택값입니다. BuildCommit은 `Actionfit` 또는 `Stormborn`을 `distributionProfile`로 request에 저장하고, workflow는 이 값으로 Mac runner의 로컬 시크릿 번들에서 어떤 회사 credential을 읽을지 결정합니다.

`Development Build`는 연결된 `BuildSettingsSO.developmentBuild`에 저장되는 기본 OFF 옵션입니다. Custom Symbols 설치 여부와 관계없이 AutoBuild 창에 표시되며 기존 `DEV` scripting define 설정과는 독립적입니다. 요청을 생성할 때 값을 고정해 두고, CI가 실제 Android/iOS 빌드 직전에 설정에 적용합니다. 활성화하면 Android working request는 APK와 Store 미업로드로 강제됩니다. 전체 요청이 성공하면 같은 Unity runner가 새 APK를 로컬 경로에서 Slack으로 직접 전송하므로 GitHub APK Artifact나 별도 delivery runner를 사용하지 않습니다. iOS working request는 마케팅 버전을 유지하고 빌드 번호를 `1`부터 시작합니다. CI가 같은 마케팅 버전의 완료된 빌드와 진행 중 업로드를 조회해 이미 사용된 최대 번호보다 1 큰 값을 작업용 요청에 적용한 뒤 TestFlight에 올립니다. 원본 BuildRequest와 BuildSettingsSO의 번들 번호는 변경하지 않습니다.

## BuildRequest schema 12

Schema 12는 저장소 루트 기준 Unity 프로젝트 경로, 자동 심볼 설정과 Development Build 선택을 요청에 기록합니다.

```json
{
  "schemaVersion": 12,
  "triggerSource": "BuildCommit",
  "unityProjectPath": "KnitFactory",
  "autoConfigureBuildSymbols": true,
  "developmentBuild": false,
  "distributionProfile": 0
}
```

`unityProjectPath`는 절대 경로나 `..`를 허용하지 않는 Git 저장소 내부 상대경로입니다. Workflow의 `resolve-unity-project.sh`가 이를 검증한 뒤 `UNITY_PROJECT_DIR`, `UNITY_LIBRARY_DIR`, `UNITY_BUILD_DIR`, 로그와 iOS 출력 경로를 파생합니다. 현재 코드와 workflow는 schema 12만 허용하므로 이전 요청은 AutoBuild 창에서 다시 생성해야 합니다.

## 적용 방법

1. `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 확인합니다.
2. `BuildSettingsSO`에 프로젝트 값을 입력합니다.
   - Company Name
   - Development Team ID (로컬 빌드용; CI 값은 runner profile에서 주입)
   - Android Package Name
   - iOS Bundle ID
   - Build Version
   - Bundle Number
   - Android alias 및 필요한 iOS / Android 빌드 옵션
3. `Tools > Package > Build Automation > AutoBuild`를 실행합니다.
4. `Build Settings`에 사용할 `BuildSettingsSO`가 연결되어 있고, `Automation Settings`에 `BuildAutomationSettingsSO`가 연결되어 있는지 확인합니다. 둘 다 없으면 AutoBuild 창에서 기본 경로에 자동 생성합니다.
5. `Version Info`에서 Version과 Bundle ID 표시를 확인합니다. 코드상 Bundle ID 라벨은 실제로 `bundleNo`, 즉 빌드 번호입니다.
6. `CI Build Request`에서 Platform을 선택합니다.
   - Android
   - iOS
   - Both
   - Current
7. `Build Kind`, `Upload Target`, `Distribution Profile`을 확인합니다. Platform 선택 시 기본값이 자동 세팅됩니다.
8. `Development Build`를 확인합니다. 기본 OFF이며 켜면 CI Android/iOS 빌드 옵션에 `BuildOptions.Development`가 추가되고 Android APK 직접 Slack 전달, iOS TestFlight 빌드번호 1부터의 자동 증가 정책이 적용됩니다.
9. `자동 빌드 심볼 세팅`을 확인합니다. 기본 ON이며 `Custom Symbols 열기`에서 플랫폼 및 Build 체크를 설정합니다.
10. `Auto Sync Build Files`는 기본 ON입니다. ON이면 `Commit, Tag & Push` 실행 시 Git 저장소 루트 `.github/workflows`, `.github/actions`, `.github/scripts`가 자동 동기화됩니다.
11. 모든 `unity-mobile` runner가 접근하는 공유 `CI_SECRET_ROOT/shared`에 `slack-webhook-url`, `slack-bot-token`, `slack-channel-id`를 한 번 등록합니다. MacBook runner는 Mac Studio SMB 공유를 고정 경로에 먼저 마운트하고 runner 환경의 `CI_SECRET_ROOT`가 그 경로를 가리키게 합니다.
12. 사람 태그가 필요하면 AutoBuild 창의 `Slack Mentions`에서 `+` 버튼으로 행을 추가하고 `Mention` 체크박스, `Member ID`, `Memo`를 설정합니다. 이 목록은 `BuildAutomationSettingsSO`에 저장되어 프로젝트에서 공유됩니다. 기본 에셋 경로는 `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`입니다. `Member ID`는 raw `U12345678` 또는 `W12345678` 형식만 사용합니다. Slack markup과 표시 이름은 workflow와 업로드 helper가 제거합니다.
13. GitHub 인증 팝업이 표시되면 `Packages/com.actionfit.githubauth/README.md`의 연결 확인 절차를 따르거나 AI에게 GitHub 인증 가이드를 문의합니다.
14. `Commit, Tag & Push` 버튼을 실행합니다. `Slack Mentions`에서 `Mention`이 체크된 행의 `Member ID` 값만 `.build/build_request.json`에 JSON 배열 `slackMentions`로 직렬화되어 해당 BuildCommit 요청에 저장됩니다. `Memo`는 공유 SO에 저장되지만 request에는 포함되지 않고 AutoBuild 창에서 식별용으로만 보입니다.

```json
"slackMentions": [
  "U12345678",
  "W23456789"
]
```

## Custom Symbols 자동 설정

`자동 빌드 심볼 세팅`은 `BuildAutomationSettingsSO.autoConfigureBuildSymbols`에 저장되고 schema 12의 `autoConfigureBuildSymbols`로 전달됩니다. 활성화하면 Build Automation이 `CustomSymbolsSO.FindOrCreateSettingsAsset()`으로 설정을 준비합니다. 기존 설정이 없으면 `Assets/_Data/_CustomSymbols/SymbolsSettings.asset`이 현재 Standalone/Android/iOS 심볼과 활성 Build/플랫폼 상태로 생성됩니다. 이후 `SwitchToRequestBuildTarget` 프로세스가 `CustomSymbolsSO.GetBuildSymbols(BuildTarget)` 결과를 대상 플랫폼의 scripting define symbols에 먼저 저장하고 종료합니다. 다음 `BuildFromRequest` Unity 프로세스는 새 심볼로 재컴파일된 상태에서 시작하며, 실제 빌드 전에 현재 심볼이 예상 목록과 정확히 일치하는지 검증합니다. 설정 생성 실패나 심볼 불일치는 빌드를 실패시킵니다.

옵션을 끄면 Build Automation은 Custom Symbols를 적용하거나 검증하지 않습니다. Build 전처리기에서 뒤늦게 define symbols를 바꾸는 방식이 아니므로, CI에서는 target switch와 실제 build를 반드시 별도 Unity 프로세스로 유지해야 합니다.

## CI Build

원격 빌드머신은 BuildCommit이 태그로 지정한 저장 커밋에서 Git 저장소 루트 `.build/build_request.json`을 읽어 같은 `BuildSettingsSO` 기반 빌드를 재현합니다. `CIBuildEntry`는 request의 `triggerSource`가 `BuildCommit`인 경우만 처리하며, 현재 Unity 프로젝트 위치가 request의 `unityProjectPath`와 다르면 실패합니다.

CI는 request의 `developmentBuild` 값을 실제 빌드 직전에 Build Setting reflection bridge로 적용합니다. 필요한 `BuildSettingsSO.developmentBuild` 계약이 없으면 최소 Build Setting 버전 안내와 함께 즉시 실패하며, Android/iOS 빌드 프로세스는 기존 플래그를 유지한 채 `BuildOptions.Development`를 추가합니다. Development 정책은 플랫폼 working request에만 적용되어 원본 요청을 보존합니다. Android는 현재 phase marker 이후 생성된 APK만 직접 Slack 전송 대상으로 인정하고 Google Play를 건너뜁니다. Slack API나 공유 credential 접근이 실패하면 `BUILD SUCCESS / APK DELIVERY FAILED` 경고를 보내되 성공한 Unity 빌드 결과는 유지합니다. iOS는 Unity 빌드 전에 App Store Connect의 공식 `apps`, `builds`, `buildUploads` API로 완료되었거나 처리 중인 동일 버전의 모든 정수 빌드 번호를 조회하고 `max(1, 사용된 최대 번호 + 1)`을 iOS working request에 원자적으로 적용합니다. API 인증, 페이지 조회, 응답 형식 또는 번호 검증이 실패하면 임의 번호로 진행하지 않고 Unity 빌드 전에 중단합니다.

```bash
Unity -batchmode -quit -projectPath "$UNITY_PROJECT_DIR" -executeMethod ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest
```

GitHub Actions workflow는 `PrepareBuildSequence`를 먼저 실행합니다. 단일 플랫폼 요청은 해당 플랫폼만 선택하고, Both 요청은 현재 active build target이 Android면 Android → iOS, iOS면 iOS → Android, 그 외에는 Android → iOS 순서로 정합니다. 이 프로세스는 원본 `.build/build_request.json`을 수정하지 않고 `.build/ci/build_request_android.json`, `.build/ci/build_request_ios.json` working copy를 만든 뒤 첫 target과 심볼을 준비합니다. working request는 고정 경로만 허용하며 repository 밖 경로, 다른 파일명, symbolic link 경로는 거부합니다.

첫 플랫폼은 별도 Unity 실행에서 바로 `BuildFromRequest`를 호출합니다. Both의 두 번째 플랫폼은 다시 별도 Unity 실행에서 `SwitchToRequestBuildTarget`을 호출한 뒤 별도 `BuildFromRequest`를 실행합니다. 따라서 기존처럼 플랫폼별 Editor assembly 재컴파일 경계를 유지하면서 정상 Both 빌드의 플랫폼 전환은 1회로 제한됩니다. 첫 플랫폼이 실패해도 두 번째 플랫폼을 시도하고, 마지막 집계 단계에서 전체 workflow를 실패 처리합니다.

Both 요청에서 첫 플랫폼의 Store 업로드는 IPA 또는 AAB, mapping, native debug symbols가 준비되는 즉시 별도 worker에서 시작합니다. workflow는 업로드와 동시에 두 번째 플랫폼 switch/build를 진행하고, 두 번째 플랫폼 단계가 끝난 뒤 첫 업로드 결과를 회수합니다. 업로드가 끝나기 전에는 첫 플랫폼 산출물과 API credential을 유지하며, artifact 업로드와 cleanup은 worker 종료 뒤 실행합니다. 단일 플랫폼과 Both의 두 번째 플랫폼은 기존처럼 해당 composite action 안에서 Store 업로드를 완료합니다.

TestFlight 업로드는 매 시도마다 새 임시 세션을 사용하며 기본 15분 hard timeout과 최대 2회 전체 프로세스 재시도를 적용합니다. `pilot` 또는 하위 `altool`이 네트워크 단절 뒤 내부 재시도에 머물면 process group을 종료하고 새 세션으로 한 번만 다시 시도합니다. workflow의 deferred Store worker는 기본 60분 상한이며, 전체 mobile job은 기존 180분 빌드 예산 뒤 최대 30분 Slack 파일 전송과 최종 정리를 수행할 수 있도록 220분 상한을 사용합니다.

모바일 빌드 workflow template은 `WorkflowTemplates/buildcommit-auto-build.yml`에 있습니다. 플랫폼 단계 원본은 `.github/actions/build-android/action.yml`, `.github/actions/build-ios/action.yml`, workflow가 호출하는 script 원본은 패키지의 `.github/scripts/`에 있습니다. `resolve-unity-project.sh`는 request의 `unityProjectPath`로 Unity 프로젝트 디렉터리와 모든 파생 경로를 결정하고, `resolve-local-secret-root.sh`는 runner별 환경 또는 Mac Studio SMB 마운트에서 공유 credential root를 결정합니다. `prepare-actionfit-private-package-access.sh`는 해당 프로젝트의 `Packages/manifest.json`에 필요한 private package 접근을 준비하고, `validate-local-runner-secrets.sh`는 Unity Mac runner secret bundle을 검증합니다.

`AutoBuild` 창의 `Update GitHub Workflow` 버튼은 package workflow template을 Git 저장소 루트의 `.github/workflows/`, 그리고 build composite actions와 scripts를 `.github/actions/`, `.github/scripts/`로 복사합니다. 기존 파일이 template과 다르면 확인창을 띄운 뒤 덮어씁니다. 이전 `buildcommit-slack-delivery.yml`이 남아 있으면 obsolete workflow로 제거합니다.

Development Android APK는 Android/iOS, 지연 Store 업로드, 최종 cleanup과 실패 집계가 모두 성공한 뒤 같은 `mobile-build` job에서 Slack external upload API로 직접 전송합니다. 성공 메시지는 APK 게시물의 `initial_comment`에 포함하므로 별도 성공 webhook을 보내지 않습니다. APK 누락이나 확정된 Slack 업로드 실패는 Unity 원본 빌드 결과를 변경하지 않고 `BUILD SUCCESS / APK DELIVERY FAILED` webhook을 시도합니다. Slack API 호출은 bounded timeout을 사용하며, 공유 `state/slack-apk-delivery`의 run별 영수증이 GitHub 재실행과 runner 변경에서도 중복 게시를 차단합니다. Slack 완료 결과가 불명확하면 pending 영수증을 보존하고 모순되는 실패 webhook을 보내지 않으며 운영자가 Slack 게시 여부를 확인한 뒤에만 해소합니다. Store 업로드에 성공한 AAB/IPA는 해당 upload step의 정확한 outcome으로 판정해 GitHub에 중복 보관하지 않습니다. 이번 phase marker 이후 staging된 Store 실패 복구 산출물은 3일, 실패 진단 로그는 7일만 보존합니다. 이 복구용 Artifact는 APK 전달과 무관하며 quota나 전송 오류를 성공으로 숨기지 않습니다.

workflow는 먼저 전용 `mobile-build-allocator` runner group과 `runner-allocator` 라벨에서 `allocate` job을 실행합니다. 이 job은 repository를 checkout하지 않고 `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner`만 호출합니다. `UNITY_RUNNER_AFFINITY_LABEL` 저장소 variable이 있으면 그 값을 사용하고, 없으면 repository 이름을 소문자 slug로 바꿔 `project-*` 라벨을 만듭니다(예: `Cat_Merge_Cafe` → `project-cat-merge-cafe`).

host-local allocator는 파일 lock으로 조직 전체의 최초 배정을 직렬화합니다. 기존 라벨 매핑이 있으면 online `unity-mobile` runner인지 검증해 재사용하고, 없으면 `unity-mobile`이면서 `ci`, `ci-validation`, `unity-package-ci`, `runner-allocator`가 없는 online runner 중 `project-*` 라벨 수가 가장 적은 대상을 선택합니다. 같은 라벨 수에서는 idle runner를 우선하지만 busy runner도 후보로 유지해 빌드가 대기열에 들어갈 수 있게 합니다. GitHub 인증은 allocator Mac 사용자의 `gh` Keychain 항목에서 읽으므로 Actions secret `UNITY_RUNNER_ALLOCATOR_TOKEN`은 사용하지 않습니다. 전용 runner, 로컬 실행 파일, GitHub 인증, runner API 또는 후보가 준비되지 않으면 `mobile-build`를 예약하기 전에 명시적으로 실패합니다.

allocator가 출력한 라벨로 `mobile-build` job이 `self-hosted`, `macOS`, `unity-mobile`, `project-*` 조합을 요청합니다. 실제 실행 runner가 allocator output과 일치하는지 확인한 뒤 workspace 상위에 `.unity-mobile-affinity.json`을 원자적으로 갱신해 host cleanup의 affinity 보존 정책을 적용합니다. 하나의 `mobile-build` job이 같은 Mac과 workspace에서 Android/iOS를 순차 실행합니다.

checkout 전에는 tracked 파일과 non-ignored untracked 파일만 정리하고, `actions/checkout`은 `clean: false`로 실행합니다. 따라서 runner-local `$UNITY_PROJECT_DIR/Library`가 보존되어 다음 빌드에서 재사용됩니다. `Library/SourceAssetDB`가 없을 때만 원격 `actions/cache/restore`를 cold fallback으로 사용하며 원격 cache save는 실행하지 않습니다. 마지막 cleanup은 working request와 임시 credential 파일만 제거하고 `Library`는 유지합니다.

ignored build output도 checkout에서 보존되므로 workflow는 승인된 BuildCommit 실행마다 `Logs`를 먼저 비우고, Android 업로드 대상은 현재 phase 시작 marker 이후 생성된 AAB와 보조 파일만 비운 transient upload 디렉터리로 복사합니다. 복구 Artifact는 이 staging output만 참조하고 affinity workspace의 과거 build glob은 스캔하지 않습니다. iOS는 재빌드 전에 고정된 Xcode project/archive/export 경로만 비우며, versioned build 보존 루트와 `Library` 전체를 초기화하지 않습니다.

Android keystore와 signing 비밀번호는 BuildRequest 값을 우선 사용하고, 값이 없을 때 Unity Mac runner의 공유 시크릿 번들로 fallback합니다. Google Play service account, iOS team id, App Store Connect API key, certificate, keychain password와 Slack credential도 이 번들에서 읽습니다. `resolve-local-secret-root.sh`는 runner 환경의 `CI_SECRET_ROOT`를 우선하고, Mac Studio 로컬 `$HOME/workspace/build-automation`, MacBook의 `/Volumes/ActionFitBuildAutomation`, `$HOME/ci-secrets/build-automation` 순서로 fallback합니다. 운영에서는 각 runner 서비스에 고정 `CI_SECRET_ROOT`를 지정하고 SMB를 runner 시작 전에 마운트합니다. 수동 validator 실행은 credential 값을 출력하지 않으며, GitHub `::add-mask::` 명령은 `GITHUB_ACTIONS=true`일 때만 출력합니다.

Shell 회귀 테스트는 로컬 validator 케이스에 `GITHUB_ACTIONS=false`, GitHub Actions 마스킹 케이스에 `GITHUB_ACTIONS=true`를 명시합니다. 따라서 테스트를 Actions 내부에서 실행해도 부모 환경을 잘못 상속하지 않으며, Actions 케이스에서는 fixture credential이 `::add-mask::` 명령 밖으로 출력되지 않는지 별도로 검증합니다.

Workflow는 패키지 import 전에 Git 저장소 루트 `.github/scripts/`를 호출합니다. Unity editor와 cache는 `$UNITY_PROJECT_DIR/ProjectSettings`, `$UNITY_PROJECT_DIR/Packages`, `$UNITY_PROJECT_DIR/Library`에서 결정하고, 빌드/로그는 `$UNITY_PROJECT_DIR/Builds`, `$UNITY_PROJECT_DIR/Logs` 아래에 생성합니다. Google Play 임시 업로드 파일과 BuildRequest만 저장소 루트 `.build` 아래에 둡니다. Path resolve 단계가 실패하면 파생 경로를 사용하는 artifact upload도 실행하지 않습니다. Artifact와 iOS signing의 상세 동작은 `RunnerSetup/` 문서를 참고합니다.

상세 Mac 서버와 공유 credential 준비 절차는 [MAC_SELF_HOSTED_RUNNER_SETUP.md](MAC_SELF_HOSTED_RUNNER_SETUP.md), [RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md](RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md)를 참고합니다.

## 의존성

- `com.actionfit.buildsetting@1.1.11` 이상
- `com.actionfit.githubauth@1.0.8` 이상
- `com.actionfit.customsymbols@1.0.7` 이상
- Unity `6000.2`
- Android/iOS 빌드용 Unity modules
- GitHub Actions self-hosted macOS runner

Build Automation은 `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, `iOSBuildProcess`를 Build Setting 패키지에서 사용합니다.
