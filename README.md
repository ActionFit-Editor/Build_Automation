# Build Automation (com.actionfit.buildautomation)

ActionFit Unity 프로젝트에서 BuildCommit 기반 자동 빌드 요청과 macOS self-hosted GitHub Actions 모바일 빌드를 관리하는 에디터 패키지입니다.

이 패키지는 `com.actionfit.buildsetting`의 빌드 설정과 `com.actionfit.customsymbols`의 build 체크 심볼을 사용합니다. Build Automation은 빌드 메타데이터와 프로젝트별 Android keystore Base64 및 signing 비밀번호를 BuildRequest에 저장합니다. Google Play, iOS, App Store Connect, certificate와 keychain credential은 self-hosted runner에서 읽습니다.

## 설치

```json
{
  "dependencies": {
    "com.actionfit.buildsetting": "https://github.com/ActionFit-Editor/Build_Setting.git#1.1.9",
    "com.actionfit.githubauth": "https://github.com/ActionFit-Editor/AI_GitHub.git#1.0.6",
    "com.actionfit.customsymbols": "https://github.com/ActionFit-Editor/Custom_Symbols.git#1.0.6",
    "com.actionfit.buildautomation": "https://github.com/ActionFit-Editor/Build_Automation.git#1.0.40"
  }
}
```

`Build_Automation` 또는 `AI_GitHub` 레포와 태그가 아직 배포되지 않았다면 위 URL은 배포 후 사용할 수 있습니다.

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
- Workflow script templates: `.github/scripts/resolve-unity-project.sh`, `.github/scripts/resolve-unity-editor.sh`, `.github/scripts/validate-local-runner-secrets.sh`, `.github/scripts/prepare-actionfit-private-package-access.sh`, `.github/scripts/notify-slack-build-result.sh`, `.github/scripts/cleanup-old-build-artifacts.sh`
- Workflow sync: `AutoBuild` 창의 `Update GitHub Workflow` 버튼
- 자동 빌드 설정 에셋: `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`
- Mac runner guide: `MAC_SELF_HOSTED_RUNNER_SETUP.md`

## AutoBuild

`AutoBuild` 창은 연결된 `BuildSettingsSO`의 버전과 번들 번호를 `PlayerSettings`에 적용한 뒤 Git 저장소 루트의 `.build/build_request.json`을 생성합니다. Unity 프로젝트가 저장소 루트에 있으면 `unityProjectPath`는 `.`, `KnitFactory/Assets`처럼 nested 구조이면 `KnitFactory`가 됩니다. 그 다음 `[BuildRequest] v{version}({bundleNo})` 형식의 저장용 커밋을 만들고 push한 뒤, `build/{platform}-{upload}/{version}/{bundleNo}-{shortSha}` 형식의 태그를 생성해 push합니다. `BuildSettingsSO`가 없으면 Build Setting 패키지가 Unity 프로젝트의 `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 자동 생성하고 `PlayerSettings` 기본값을 1차 초기화합니다.

`Commit, Tag & Push`는 Unity를 실행 중인 로컬 기기의 `git push`와 tag push 권한을 사용합니다. 자동빌드를 요청하는 각 개발자 기기는 해당 GitHub repository에 push/tag 권한이 있는 계정으로 Git 인증을 먼저 설정해야 합니다. BuildCommit은 커밋 생성 전에 `com.actionfit.githubauth`의 preflight를 reflection으로 호출하고, 인증이 없으면 GitHub 인증 필요 팝업을 띄운 뒤 중단합니다. `com.actionfit.buildsetting`, `com.actionfit.customsymbols` 또는 `com.actionfit.githubauth`가 누락된 프로젝트에서는 필요한 기능을 막고 의존성 설치를 안내합니다. ActionFit Package Manager로 설치/업데이트하면 catalog CSV의 dependency 정보가 Unity 프로젝트의 `Packages/manifest.json`에 Git UPM URL로 함께 기록됩니다. 수동으로 manifest를 편집하는 경우에는 Build Automation, Build Setting, Custom Symbols, AI GitHub Git UPM URL을 직접 추가해야 합니다. 자세한 GitHub 연결 확인 순서와 오류별 안내는 `Packages/com.actionfit.githubauth/README.md`를 확인합니다.

`CS0103: The name 'BuildSettingBridge' does not exist in the current context`가 발생하면 `com.actionfit.buildautomation`을 `1.0.25` 이상으로 업데이트한 뒤 `AssetDatabase.Refresh` 또는 Unity 재시작으로 스크립트 컴파일 목록을 갱신합니다. 이 버전부터 bridge 타입은 Unity가 이미 컴파일하는 소스에 포함되어 부분 refresh 상태에서도 BuildAutomation 참조가 깨지지 않도록 되어 있습니다.

`Auto Sync Build Files`는 기본값이 켜짐입니다. 켜져 있으면 `Commit, Tag & Push` 실행 시 Build Automation 패키지의 workflow/template scripts를 Git 저장소 루트 `.github/`로 먼저 동기화하고, 그 변경분도 같은 저장 커밋에 포함합니다. GitHub 제약상 workflow 위치는 항상 저장소 루트 `.github/workflows`이고 Unity 프로젝트가 nested인지와 무관합니다.

`AutoBuild` 창 본문은 세로 스크롤 영역입니다. 창 높이가 낮아져도 Version Info, CI Build Request, GitHub Workflow, 버튼, Log 순서가 유지되며 Log 영역은 별도 스크롤을 사용합니다.

실제 GitHub Actions 빌드 요청은 저장 커밋 push가 아니라 `build/**` 태그 push로 발생합니다. 저장 커밋은 요청 JSON과 변경사항을 남기는 용도이며, 같은 버전으로 재요청할 수 있도록 커밋은 `--allow-empty`를 허용합니다.

Android/iOS Unity batchmode 빌드가 실패하면 workflow가 `$UNITY_PROJECT_DIR/Logs/unity-android.log` 또는 `$UNITY_PROJECT_DIR/Logs/unity-ios.log` 마지막 400줄을 GitHub Actions log group에 출력합니다. 따라서 실패 원인 확인을 위해 먼저 artifact를 내려받지 않아도 됩니다.

`Platform` 기본값은 `None`이며, 플랫폼을 선택하지 않으면 `Commit, Tag & Push` 버튼이 비활성화됩니다. `Current`, Android, iOS, Both 중 하나를 명시적으로 선택해야 BuildCommit request를 만들 수 있습니다. `Current`를 직접 선택한 경우에는 Unity의 현재 active build target을 기준으로 Android 또는 iOS 요청으로 해석됩니다.

`Platform` 선택 시 `Build Kind`와 `Upload Target`은 자동 기본값으로 맞춰집니다. Android는 `AndroidAab`와 `GooglePlayInternal`, iOS는 `iOSXcodeProject`와 `TestFlight`, Both는 `Android AAB + iOS Xcode Project`와 `GooglePlayInternalAndTestFlight`를 사용합니다.

Android 요청에는 `androidKeystoreFileName`, `androidKeystoreBase64`, `androidKeystorePassword`, `androidAliasPassword`, `androidKeyaliasName`을 저장합니다. Android 빌드는 request의 keystore Base64와 두 비밀번호를 우선 사용하고, 해당 값이 비어 있을 때만 runner의 `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_PASS`를 fallback으로 사용합니다. Google Play JSON, iOS team credential, App Store Connect API key, certificate와 keychain 비밀번호는 runner 로컬 secret bundle에서 읽습니다.

Android package name은 `BuildSettingsSO.androidPackageName`, iOS bundle id는 `BuildSettingsSO.iosPackageName` 값을 request에 함께 저장합니다. workflow는 이 request 값을 Google Play `packageName`과 TestFlight `app_identifier`로 사용하므로, profile별 package/bundle id를 workflow env에 따로 적지 않습니다.

`Distribution Profile`은 배포 계정 선택값입니다. BuildCommit은 `Actionfit` 또는 `Stormborn`을 `distributionProfile`로 request에 저장하고, workflow는 이 값으로 Mac runner의 로컬 시크릿 번들에서 어떤 회사 credential을 읽을지 결정합니다.

## BuildRequest schema 11

Schema 11은 저장소 루트 기준 Unity 프로젝트 경로와 자동 심볼 설정을 요청에 기록합니다.

```json
{
  "schemaVersion": 11,
  "triggerSource": "BuildCommit",
  "unityProjectPath": "KnitFactory",
  "autoConfigureBuildSymbols": true,
  "distributionProfile": 0
}
```

`unityProjectPath`는 절대 경로나 `..`를 허용하지 않는 Git 저장소 내부 상대경로입니다. Workflow의 `resolve-unity-project.sh`가 이를 검증한 뒤 `UNITY_PROJECT_DIR`, `UNITY_LIBRARY_DIR`, `UNITY_BUILD_DIR`, 로그와 iOS 출력 경로를 파생합니다. 현재 코드와 workflow는 schema 11만 허용하므로 이전 요청은 AutoBuild 창에서 다시 생성해야 합니다.

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
8. `자동 빌드 심볼 세팅`을 확인합니다. 기본 ON이며 `Custom Symbols 열기`에서 플랫폼 및 Build 체크를 설정합니다.
9. `Auto Sync Build Files`는 기본 ON입니다. ON이면 `Commit, Tag & Push` 실행 시 Git 저장소 루트 `.github/workflows`와 `.github/scripts`가 자동 동기화됩니다.
10. Slack 알림이 필요하면 Mac runner 로컬 시크릿 번들에 `shared/slack-webhook-url`을 설정합니다.
11. 사람 태그가 필요하면 AutoBuild 창의 `Slack Mentions`에서 `+` 버튼으로 행을 추가하고 `Mention` 체크박스, `Member ID`, `Memo`를 설정합니다. 이 목록은 `BuildAutomationSettingsSO`에 저장되어 프로젝트에서 공유됩니다. 기본 에셋 경로는 `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`입니다. `Member ID` 예: `U12345678`, `<@U23456789>`. 표시 이름 `@송제우`는 실제 멘션 알림으로 동작하지 않을 수 있습니다.
12. GitHub 인증 팝업이 표시되면 `Packages/com.actionfit.githubauth/README.md`의 연결 확인 절차를 따르거나 AI에게 GitHub 인증 가이드를 문의합니다.
13. `Commit, Tag & Push` 버튼을 실행합니다. `Slack Mentions`에서 `Mention`이 체크된 행의 `Member ID` 값만 `.build/build_request.json`에 JSON 배열 `slackMentions`로 직렬화되어 해당 BuildCommit 요청에 저장됩니다. `Memo`는 공유 SO에 저장되지만 request에는 포함되지 않고 AutoBuild 창에서 식별용으로만 보입니다.

```json
"slackMentions": [
  "U12345678",
  "<@U23456789>"
]
```

## Custom Symbols 자동 설정

`자동 빌드 심볼 세팅`은 `BuildAutomationSettingsSO.autoConfigureBuildSymbols`에 저장되고 schema 11의 `autoConfigureBuildSymbols`로 전달됩니다. 활성화하면 Build Automation이 `CustomSymbolsSO.FindOrCreateSettingsAsset()`으로 설정을 준비합니다. 기존 설정이 없으면 `Assets/_Data/_CustomSymbols/SymbolsSettings.asset`이 현재 Standalone/Android/iOS 심볼과 활성 Build/플랫폼 상태로 생성됩니다. 이후 `SwitchToRequestBuildTarget` 프로세스가 `CustomSymbolsSO.GetBuildSymbols(BuildTarget)` 결과를 대상 플랫폼의 scripting define symbols에 먼저 저장하고 종료합니다. 다음 `BuildFromRequest` Unity 프로세스는 새 심볼로 재컴파일된 상태에서 시작하며, 실제 빌드 전에 현재 심볼이 예상 목록과 정확히 일치하는지 검증합니다. 설정 생성 실패나 심볼 불일치는 빌드를 실패시킵니다.

옵션을 끄면 Build Automation은 Custom Symbols를 적용하거나 검증하지 않습니다. Build 전처리기에서 뒤늦게 define symbols를 바꾸는 방식이 아니므로, CI에서는 target switch와 실제 build를 반드시 별도 Unity 프로세스로 유지해야 합니다.

## CI Build

원격 빌드머신은 BuildCommit이 태그로 지정한 저장 커밋에서 Git 저장소 루트 `.build/build_request.json`을 읽어 같은 `BuildSettingsSO` 기반 빌드를 재현합니다. `CIBuildEntry`는 request의 `triggerSource`가 `BuildCommit`인 경우만 처리하며, 현재 Unity 프로젝트 위치가 request의 `unityProjectPath`와 다르면 실패합니다.

```bash
Unity -batchmode -quit -projectPath "$UNITY_PROJECT_DIR" -executeMethod ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest
```

GitHub Actions workflow는 Android/iOS 실제 빌드 실행 전에 Unity를 같은 target으로 한 번 더 실행해 `SwitchToRequestBuildTarget`만 호출합니다. 이 단계는 `.build/build_request.json`의 `platform`을 읽고 `EditorUserBuildSettings.SwitchActiveBuildTarget(...)`으로 active build target을 맞춘 뒤 종료합니다. 그 다음 별도 Unity 실행에서 `BuildFromRequest`를 호출하므로, Editor assembly가 Android/iOS 심볼로 재컴파일된 상태에서 Build Setting의 플랫폼별 build process를 찾을 수 있습니다.

기본 GitHub Actions workflow template은 `WorkflowTemplates/buildcommit-auto-build.yml`에 있고, workflow가 호출하는 script 원본은 패키지의 `.github/scripts/`에 있습니다. `resolve-unity-project.sh`는 request의 `unityProjectPath`로 Unity 프로젝트 디렉터리와 모든 파생 경로를 결정하고, `resolve-unity-editor.sh`는 해당 프로젝트의 `ProjectSettings/ProjectVersion.txt`에서 Unity 버전을 읽습니다. `prepare-actionfit-private-package-access.sh`는 해당 프로젝트의 `Packages/manifest.json`에 필요한 private package 접근을 준비하고, `validate-local-runner-secrets.sh`는 Mac runner secret bundle을 검증합니다. `notify-slack-build-result.sh`와 cleanup script도 resolve 단계에서 받은 경로를 사용합니다.

`AutoBuild` 창의 `Update GitHub Workflow` 버튼은 package template을 Git 저장소 루트의 `.github/workflows/buildcommit-auto-build.yml`, `.github/scripts/`로 복사합니다. 기존 파일이 template과 다르면 확인창을 띄운 뒤 덮어씁니다.

workflow는 macOS self-hosted runner 기준입니다. runner에는 `self-hosted`, `macOS`, `unity-mobile` 라벨이 있어야 하며, 같은 Mac에서 Unity CLI로 Android/iOS를 빌드합니다. `Platform=Both` 요청은 workflow가 Android job과 iOS job으로 나눠 `.build/build_request.json`의 platform 값을 임시 변환한 뒤, 각 job에서 `SwitchToRequestBuildTarget`와 `BuildFromRequest`를 별도 Unity 실행으로 순서대로 호출합니다.

Android keystore와 signing 비밀번호는 BuildRequest 값을 우선 사용하고, 값이 없을 때 Mac runner의 로컬 시크릿 번들로 fallback합니다. Google Play service account, iOS team id, App Store Connect API key, certificate, keychain password, Slack webhook URL은 runner 로컬 번들에서 읽습니다. 기본 workflow template은 기존 ActionFit runner bundle을 계속 사용하도록 `CI_SECRET_ROOT=/Users/lydia/workspace/build-automation`을 명시하며, setup/validation script를 workflow 밖에서 직접 실행해 이 환경변수가 없으면 `$HOME/ci-secrets/build-automation`으로 fallback합니다. 수동 validator 실행은 credential 값을 출력하지 않으며, GitHub `::add-mask::` 명령은 `GITHUB_ACTIONS=true`일 때만 출력합니다.

Workflow는 패키지 import 전에 Git 저장소 루트 `.github/scripts/`를 호출합니다. Unity editor와 cache는 `$UNITY_PROJECT_DIR/ProjectSettings`, `$UNITY_PROJECT_DIR/Packages`, `$UNITY_PROJECT_DIR/Library`에서 결정하고, 빌드/로그는 `$UNITY_PROJECT_DIR/Builds`, `$UNITY_PROJECT_DIR/Logs` 아래에 생성합니다. Google Play 임시 업로드 파일과 BuildRequest만 저장소 루트 `.build` 아래에 둡니다. Path resolve 단계가 실패하면 파생 경로를 사용하는 artifact upload도 실행하지 않습니다. Artifact와 iOS signing의 상세 동작은 `RunnerSetup/` 문서를 참고합니다.

상세 Mac 서버 준비 절차는 [MAC_SELF_HOSTED_RUNNER_SETUP.md](MAC_SELF_HOSTED_RUNNER_SETUP.md)를 참고합니다.

## 의존성

- `com.actionfit.buildsetting@1.1.9` 이상
- `com.actionfit.githubauth@1.0.6` 이상
- `com.actionfit.customsymbols@1.0.6` 이상
- Unity `6000.2`
- Android/iOS 빌드용 Unity modules
- GitHub Actions self-hosted macOS runner

Build Automation은 `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, `iOSBuildProcess`를 Build Setting 패키지에서 사용합니다.
