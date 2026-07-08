# Build Automation (com.actionfit.buildautomation)

ActionFit Unity 프로젝트에서 BuildCommit 기반 자동 빌드 요청과 macOS self-hosted GitHub Actions 모바일 빌드를 관리하는 에디터 패키지입니다.

이 패키지는 `com.actionfit.buildsetting`의 빌드 설정을 사용합니다. 버전, 번들 번호, Android/iOS 빌드 경로, signing 관련 설정은 `BuildSettingsSO`에 저장하고, Build Automation은 그 설정을 기반으로 원격 CI 요청을 만듭니다.

## 설치

```json
{
  "dependencies": {
    "com.actionfit.buildsetting": "https://github.com/ActionFit-Editor/Build_Setting.git#1.1.3",
    "com.actionfit.githubauth": "https://github.com/ActionFit-Editor/GitHub_Auth.git#1.0.1",
    "com.actionfit.buildautomation": "https://github.com/ActionFit-Editor/Build_Automation.git#1.0.24"
  }
}
```

`Build_Automation` 또는 `GitHub_Auth` 레포와 태그가 아직 배포되지 않았다면 위 URL은 배포 후 사용할 수 있습니다.

## 구성

- 메뉴: `Tools > ActionFit > BuildSetting > AutoBuild`
- 요청 파일: `.build/build_request.json`
- CI 진입점: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`
- Workflow script templates: `.github/scripts/resolve-unity-editor.sh`, `.github/scripts/validate-local-runner-secrets.sh`, `.github/scripts/prepare-actionfit-private-package-access.sh`, `.github/scripts/notify-slack-build-result.sh`
- Workflow sync: `AutoBuild` 창의 `Update GitHub Workflow` 버튼
- 자동 빌드 설정 에셋: `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`
- Mac runner guide: `MAC_SELF_HOSTED_RUNNER_SETUP.md`

## AutoBuild

`AutoBuild` 창은 연결된 `BuildSettingsSO`의 버전과 번들 번호를 `PlayerSettings`에 적용한 뒤, `.build/build_request.json`을 생성합니다. 그 다음 `[BuildRequest] v{version}({bundleNo})` 형식의 저장용 커밋을 만들고 push한 뒤, `build/{platform}-{upload}/{version}/{bundleNo}-{shortSha}` 형식의 태그를 생성해 push합니다. `BuildSettingsSO`가 없으면 Build Setting 패키지가 `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 자동 생성하고 프로젝트 `PlayerSettings` 기본값을 1차 초기화합니다.

`Commit, Tag & Push`는 Unity를 실행 중인 로컬 기기의 `git push`와 tag push 권한을 사용합니다. 자동빌드를 요청하는 각 개발자 기기는 해당 GitHub repository에 push/tag 권한이 있는 계정으로 Git 인증을 먼저 설정해야 합니다. BuildCommit은 커밋 생성 전에 `com.actionfit.githubauth`의 preflight를 reflection으로 호출하고, 인증이 없으면 GitHub 인증 필요 팝업을 띄운 뒤 중단합니다. `com.actionfit.buildsetting` 또는 `com.actionfit.githubauth`가 누락된 프로젝트에서는 BuildAutomation이 컴파일은 유지하지만 AutoBuild 실행을 막고 의존성 설치를 안내합니다. ActionFit Package Manager로 설치/업데이트하면 catalog CSV의 dependency 정보가 `Packages/manifest.json`에 Git UPM URL로 함께 기록됩니다. 수동으로 `Packages/manifest.json`을 편집하는 경우에는 BuildAutomation뿐 아니라 Build Setting과 GitHub Auth Git UPM URL도 직접 추가해야 합니다. 자세한 연결 확인 순서와 오류별 안내는 `Packages/com.actionfit.githubauth/README.md`를 확인합니다.

`Auto Sync Build Files`는 기본값이 켜짐입니다. 켜져 있으면 `Commit, Tag & Push` 실행 시 Build Automation 패키지의 workflow/template scripts를 프로젝트 루트 `.github/`로 먼저 동기화하고, 그 변경분도 같은 저장 커밋에 포함합니다.

실제 GitHub Actions 빌드 요청은 저장 커밋 push가 아니라 `build/**` 태그 push로 발생합니다. 저장 커밋은 요청 JSON과 변경사항을 남기는 용도이며, 같은 버전으로 재요청할 수 있도록 커밋은 `--allow-empty`를 허용합니다.

`Platform` 기본값은 `None`이며, 플랫폼을 선택하지 않으면 `Commit, Tag & Push` 버튼이 비활성화됩니다. `Current`, Android, iOS, Both 중 하나를 명시적으로 선택해야 BuildCommit request를 만들 수 있습니다. `Current`를 직접 선택한 경우에는 Unity의 현재 active build target을 기준으로 Android 또는 iOS 요청으로 해석됩니다.

`Platform` 선택 시 `Build Kind`와 `Upload Target`은 자동 기본값으로 맞춰집니다. Android는 `AndroidAab`와 `GooglePlayInternal`, iOS는 `iOSXcodeProject`와 `TestFlight`, Both는 `Android AAB + iOS Xcode Project`와 `GooglePlayInternalAndTestFlight`를 사용합니다.

Android 요청에서는 `BuildSettingsSO.keyStorePath`, `BuildSettingsSO.keyStoreAlias`, `BuildSettingsSO.keystorePassword`, `BuildSettingsSO.aliasPassword` 값을 함께 저장합니다. 즉 keystore 파일은 base64로, alias 이름과 Android signing 비밀번호는 문자열로 BuildCommit request에 직렬화됩니다. 이 동작은 Mac Studio 테스트 편의를 위한 모드이며 `.build/build_request.json` 커밋 히스토리에 signing key가 남습니다. Google Play JSON, App Store Connect API key, keychain password는 request에 저장하지 않습니다.

Android package name은 `BuildSettingsSO.androidPackageName`, iOS bundle id는 `BuildSettingsSO.iosPackageName` 값을 request에 함께 저장합니다. workflow는 이 request 값을 Google Play `packageName`과 TestFlight `app_identifier`로 사용하므로, profile별 package/bundle id를 workflow env에 따로 적지 않습니다.

`Distribution Profile`은 배포 계정 선택값입니다. BuildCommit은 `Actionfit` 또는 `Stormborn`을 `distributionProfile`로 request에 저장하고, workflow는 이 값으로 Mac runner의 로컬 시크릿 번들에서 어떤 회사 credential을 읽을지 결정합니다.

## 적용 방법

1. `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 확인합니다.
2. `BuildSettingsSO`에 프로젝트 값을 입력합니다.
   - Company Name
   - Development Team ID
   - Android Package Name
   - iOS Bundle ID
   - Build Version
   - Bundle Number
   - Android keystore / alias / password
   - 필요한 iOS / Android 빌드 옵션
3. `Tools > ActionFit > BuildSetting > AutoBuild`를 실행합니다.
4. `Build Settings`에 사용할 `BuildSettingsSO`가 연결되어 있고, `Automation Settings`에 `BuildAutomationSettingsSO`가 연결되어 있는지 확인합니다. 둘 다 없으면 AutoBuild 창에서 기본 경로에 자동 생성합니다.
5. `Version Info`에서 Version과 Bundle ID 표시를 확인합니다. 코드상 Bundle ID 라벨은 실제로 `bundleNo`, 즉 빌드 번호입니다.
6. `CI Build Request`에서 Platform을 선택합니다.
   - Android
   - iOS
   - Both
   - Current
7. `Build Kind`, `Upload Target`, `Distribution Profile`을 확인합니다. Platform 선택 시 기본값이 자동 세팅됩니다.
8. `Auto Sync Build Files`는 기본 ON입니다. ON이면 `Commit, Tag & Push` 실행 시 `.github/workflows`와 `.github/scripts`가 자동 동기화됩니다.
9. Slack 알림이 필요하면 Mac runner 로컬 시크릿 번들에 `shared/slack-webhook-url`을 설정합니다.
10. 사람 태그가 필요하면 AutoBuild 창의 `Slack Mentions`에서 `+` 버튼으로 행을 추가하고 `Mention` 체크박스, `Member ID`, `Memo`를 설정합니다. 이 목록은 `BuildAutomationSettingsSO`에 저장되어 프로젝트에서 공유됩니다. 기본 에셋 경로는 `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`입니다. `Member ID` 예: `U12345678`, `<@U23456789>`. 표시 이름 `@송제우`는 실제 멘션 알림으로 동작하지 않을 수 있습니다.
11. GitHub 인증 팝업이 표시되면 `Packages/com.actionfit.githubauth/README.md`의 연결 확인 절차를 따르거나 AI에게 GitHub 인증 가이드를 문의합니다.
12. `Commit, Tag & Push` 버튼을 실행합니다. `Slack Mentions`에서 `Mention`이 체크된 행의 `Member ID` 값만 `.build/build_request.json`에 JSON 배열 `slackMentions`로 직렬화되어 해당 BuildCommit 요청에 저장됩니다. `Memo`는 공유 SO에 저장되지만 request에는 포함되지 않고 AutoBuild 창에서 식별용으로만 보입니다.

```json
"slackMentions": [
  "U12345678",
  "<@U23456789>"
]
```

## CI Build

원격 빌드머신은 BuildCommit이 태그로 지정한 저장 커밋에서 `.build/build_request.json`을 읽어 같은 `BuildSettingsSO` 기반 빌드를 재현합니다. `CIBuildEntry`는 request의 `triggerSource`가 `BuildCommit`인 경우만 처리합니다.

```bash
Unity -batchmode -quit -projectPath . -executeMethod ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest
```

기본 GitHub Actions workflow template은 `WorkflowTemplates/buildcommit-auto-build.yml`에 있고, workflow가 호출하는 script 원본은 패키지의 `.github/scripts/`에 있습니다. `prepare-actionfit-private-package-access.sh`는 runner의 `gh auth` 또는 `CI_SECRET_ROOT/shared/github-package-read-token`으로 private GitHub UPM package 접근을 준비하고, `resolve-unity-editor.sh`는 `ProjectSettings/ProjectVersion.txt`에서 Unity 버전을 읽어 `UNITY_VERSION`, `UNITY_VERSION_WITH_REVISION`, `UNITY_EXECUTABLE`을 이후 step으로 전달하고, `validate-local-runner-secrets.sh`는 Mac runner secret bundle을 검증합니다. `notify-slack-build-result.sh`는 Android/iOS job 마지막에 실행되어 `CI_SECRET_ROOT/shared/slack-webhook-url`이 있을 때 짧은 빌드 결과를 Slack으로 보냅니다. BuildCommit request의 `slackMentions` 배열이 있으면 여러 Slack member ID를 메시지 첫 줄에 붙입니다. 프로젝트에서 사용하려면 workflow는 `.github/workflows/buildcommit-auto-build.yml`로, scripts는 `.github/scripts/`로 복사한 뒤 Unity Hub root, Xcode 경로 같은 프로젝트별 env 값을 조정합니다.
`AutoBuild` 창의 `Update GitHub Workflow` 버튼은 패키지의 workflow template과 script templates를 프로젝트 루트의 `.github/workflows/buildcommit-auto-build.yml`, `.github/scripts/`로 복사합니다. 기존 파일이 template과 다르면 확인창을 띄운 뒤 덮어씁니다.

workflow는 macOS self-hosted runner 기준입니다. runner에는 `self-hosted`, `macOS`, `unity-mobile` 라벨이 있어야 하며, 같은 Mac에서 Unity CLI로 Android/iOS를 빌드합니다. `Platform=Both` 요청은 workflow가 Android job과 iOS job으로 나눠 `.build/build_request.json`의 platform 값을 임시 변환한 뒤 `CIBuildEntry.BuildFromRequest`를 각각 호출합니다.

Google Play service account, iOS team id, App Store Connect API key, keychain password, Slack webhook URL은 Mac runner의 로컬 시크릿 번들에서 읽습니다. Android keystore 파일과 signing 비밀번호는 request 값을 우선 사용하고, request에 없을 때만 로컬 env로 fallback합니다. 로컬 시크릿 번들 경로는 workflow yml의 `CI_SECRET_ROOT`가 기준이며 현재 yml 값은 `/Users/lydia/workspace/build-automation`입니다. workflow는 Unity/PackageCache가 준비되기 전에 Unity editor 경로 확인과 secret 검증을 실행하므로 패키지 경로가 아니라 프로젝트 루트 `.github/scripts/` 아래의 scripts를 호출합니다. Unity editor는 workflow yml의 고정 버전이 아니라 `ProjectSettings/ProjectVersion.txt`의 `m_EditorVersion`으로 결정되며, `UNITY_HUB_EDITOR_ROOT` 아래에 해당 버전이 없으면 빌드 전에 실패합니다. Android Google Play upload는 프로젝트명을 하드코딩하지 않고 발견된 AAB를 `.build/google-play-upload/upload.aab`로 복사해 업로드하며, Android artifact는 AAB와 로그를 분리해서 올리고 `Builds/**` 전체 업로드는 하지 않습니다. iOS archive 기본 경로도 `Builds/iOSArchive/BuildCommit.xcarchive`를 사용합니다. Google Play action은 deprecated `track` 대신 `tracks` 입력을 사용합니다. iOS App Store profiles are selected by request bundle id from `ios/profiles/<bundle-id>.mobileprovision`, with optional `fastlane sigh` generation. iOS archive signing은 `xcodebuild`에 단일 `CODE_SIGN_IDENTITY`만 전달해 Xcode가 `CODE_SIGN_IDENTITY[sdk=iphoneos*]` 값을 인증서 이름으로 오해하지 않게 합니다. Android/iOS workflow는 Unity `Library` cache를 restore-only로 사용해 Google Play/TestFlight 업로드 성공 후 cache 저장 후처리가 전체 Run을 붙잡지 않게 합니다. Android/iOS artifact upload steps are `continue-on-error: true`, so GitHub artifact storage quota exhaustion does not mark an otherwise successful Google Play/TestFlight deployment as failed. iOS artifact는 성공 시 IPA/plist와 로그만, 실패 시 diagnostic 로그와 export 결과만 업로드해 `Builds/iOS/**`와 `.xcarchive` 전체 업로드로 인한 1GB급 artifact 실패를 피합니다. 설치/검증 스크립트와 상세 가이드는 `RunnerSetup/` 아래에 있습니다.

상세 Mac 서버 준비 절차는 [MAC_SELF_HOSTED_RUNNER_SETUP.md](MAC_SELF_HOSTED_RUNNER_SETUP.md)를 참고합니다.

## 의존성

- `com.actionfit.buildsetting@1.1.3` 이상
- `com.actionfit.githubauth@1.0.1` 이상
- Unity `6000.2`
- Android/iOS 빌드용 Unity modules
- GitHub Actions self-hosted macOS runner

Build Automation은 `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, `iOSBuildProcess`를 Build Setting 패키지에서 사용합니다.
