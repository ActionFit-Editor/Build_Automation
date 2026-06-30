# Build Automation (com.actionfit.buildautomation)

ActionFit Unity 프로젝트에서 BuildCommit 기반 자동 빌드 요청과 macOS self-hosted GitHub Actions 모바일 빌드를 관리하는 에디터 패키지입니다.

이 패키지는 `com.actionfit.buildsetting`의 빌드 설정을 사용합니다. 버전, 번들 번호, Android/iOS 빌드 경로, signing 관련 설정은 `BuildSettingsSO`에 저장하고, Build Automation은 그 설정을 기반으로 원격 CI 요청을 만듭니다.

## 설치

```json
{
  "dependencies": {
    "com.actionfit.buildsetting": "https://github.com/ActionFit-Editor/Build_Setting.git#1.1.2",
    "com.actionfit.buildautomation": "https://github.com/ActionFit-Editor/Build_Automation.git#1.0.8"
  }
}
```

`Build_Automation` 레포와 태그가 아직 배포되지 않았다면 위 URL은 배포 후 사용할 수 있습니다.

## 구성

- 메뉴: `Tools > ActionFit > BuildSetting > AutoBuild`
- 요청 파일: `.build/build_request.json`
- CI 진입점: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`
- Mac runner guide: `MAC_SELF_HOSTED_RUNNER_SETUP.md`

## AutoBuild

`AutoBuild` 창은 연결된 `BuildSettingsSO`의 버전과 번들 번호를 `PlayerSettings`에 적용한 뒤, `.build/build_request.json`을 생성합니다. 그 다음 `[BuildRequest] v{version}({bundleNo})` 형식의 저장용 커밋을 만들고 push한 뒤, `build/{platform}-{upload}/{version}/{bundleNo}-{shortSha}` 형식의 태그를 생성해 push합니다. `BuildSettingsSO`가 없으면 Build Setting 패키지가 `Assets/_Data/_BuildSetting/BuildSettingsSO.asset`을 자동 생성하고 프로젝트 `PlayerSettings` 기본값을 1차 초기화합니다.

실제 GitHub Actions 빌드 요청은 저장 커밋 push가 아니라 `build/**` 태그 push로 발생합니다. 저장 커밋은 요청 JSON과 변경사항을 남기는 용도이며, 같은 버전으로 재요청할 수 있도록 커밋은 `--allow-empty`를 허용합니다.

`Platform` 선택 시 `Build Kind`와 `Upload Target`은 자동 기본값으로 맞춰집니다. Android는 `AndroidAab`와 `GooglePlayInternal`, iOS는 `iOSXcodeProject`와 `TestFlight`, Both는 `Android AAB + iOS Xcode Project`와 `GooglePlayInternalAndTestFlight`를 사용합니다.

Android 요청에서는 `BuildSettingsSO.keyStoreAlias` 값을 `androidKeyaliasName`으로 함께 저장합니다. keystore password, alias password, Google Play JSON, App Store Connect API key 같은 비밀값은 request에 저장하지 않습니다.

Android package name은 `BuildSettingsSO.androidPackageName`, iOS bundle id는 `BuildSettingsSO.iosPackageName` 값을 request에 함께 저장합니다. workflow는 이 request 값을 Google Play `packageName`과 TestFlight `app_identifier`로 사용하므로, profile별 package/bundle id를 workflow env에 따로 적지 않습니다.

`Distribution Profile`은 배포 계정 선택값입니다. BuildCommit은 `Actionfit` 또는 `Stormborn`을 `distributionProfile`로 request에 저장하고, workflow는 이 값으로 Mac runner의 로컬 시크릿 번들에서 어떤 회사 credential을 읽을지 결정합니다.

## CI Build

원격 빌드머신은 BuildCommit이 태그로 지정한 저장 커밋에서 `.build/build_request.json`을 읽어 같은 `BuildSettingsSO` 기반 빌드를 재현합니다. `CIBuildEntry`는 request의 `triggerSource`가 `BuildCommit`인 경우만 처리합니다.

```bash
Unity -batchmode -quit -projectPath . -executeMethod ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest
```

기본 GitHub Actions workflow template은 `WorkflowTemplates/buildcommit-auto-build.yml`에 있습니다. 프로젝트에서 사용하려면 내용을 `.github/workflows/buildcommit-auto-build.yml`로 복사한 뒤, Unity/Xcode 경로 같은 프로젝트별 env 값을 조정합니다.

workflow는 macOS self-hosted runner 기준입니다. runner에는 `self-hosted`, `macOS`, `unity-mobile` 라벨이 있어야 하며, 같은 Mac에서 Unity CLI로 Android/iOS를 빌드합니다. `Platform=Both` 요청은 workflow가 Android job과 iOS job으로 나눠 `.build/build_request.json`의 platform 값을 임시 변환한 뒤 `CIBuildEntry.BuildFromRequest`를 각각 호출합니다.

Android signing 비밀번호와 Google Play service account, iOS team id, App Store Connect API key, keychain password는 Mac runner의 로컬 시크릿 번들에서 읽습니다. 기본 경로는 runner 사용자의 `$HOME/ci-secrets/cat-merge-cafe`이며, 필요할 때만 `CI_SECRET_ROOT`로 override합니다. 설치/검증 스크립트와 상세 가이드는 `RunnerSetup/` 아래에 있습니다.

상세 Mac 서버 준비 절차는 [MAC_SELF_HOSTED_RUNNER_SETUP.md](MAC_SELF_HOSTED_RUNNER_SETUP.md)를 참고합니다.

## 의존성

- `com.actionfit.buildsetting@1.1.2` 이상
- Unity `6000.2`
- Android/iOS 빌드용 Unity modules
- GitHub Actions self-hosted macOS runner

Build Automation은 `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, `iOSBuildProcess`를 Build Setting 패키지에서 사용합니다.
