# Build Automation (com.actionfit.buildautomation)

ActionFit Unity 프로젝트에서 BuildCommit 기반 자동 빌드 요청과 macOS self-hosted GitHub Actions 모바일 빌드를 관리하는 에디터 패키지입니다.

이 패키지는 `com.actionfit.buildsetting`의 빌드 설정을 사용합니다. 버전, 번들 번호, Android/iOS 빌드 경로, signing 관련 설정은 `BuildSettingsSO`에 저장하고, Build Automation은 그 설정을 기반으로 원격 CI 요청을 만듭니다.

## 설치

```json
{
  "dependencies": {
    "com.actionfit.buildsetting": "https://github.com/ActionFit-Editor/Build_Setting.git#1.1.1",
    "com.actionfit.buildautomation": "https://github.com/ActionFit-Editor/Build_Automation.git#1.0.7"
  }
}
```

`Build_Automation` 레포와 태그가 아직 배포되지 않았다면 위 URL은 배포 후 사용할 수 있습니다.

## 구성

- 메뉴: `Tools > ActionFit > Build Commit`
- 요청 파일: `.build/build_request.json`
- CI 진입점: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`
- Mac runner guide: `MAC_SELF_HOSTED_RUNNER_SETUP.md`

## Build Commit

`Build Commit` 창은 연결된 `BuildSettingsSO`의 버전과 번들 번호를 `PlayerSettings`에 적용한 뒤, `.build/build_request.json`을 생성합니다. 그 다음 `[BuildRequest] v{version}({bundleNo})` 형식의 저장용 커밋을 만들고 push한 뒤, `build/{platform}-{upload}/{version}/{bundleNo}-{shortSha}` 형식의 태그를 생성해 push합니다.

실제 GitHub Actions 빌드 요청은 저장 커밋 push가 아니라 `build/**` 태그 push로 발생합니다. 저장 커밋은 요청 JSON과 변경사항을 남기는 용도이며, 같은 버전으로 재요청할 수 있도록 커밋은 `--allow-empty`를 허용합니다.

`Platform` 선택 시 `Build Kind`와 `Upload Target`은 자동 기본값으로 맞춰집니다. Android는 `AndroidAab`와 `GooglePlayInternal`, iOS는 `iOSXcodeProject`와 `TestFlight`, Both는 `Android AAB + iOS Xcode Project`와 `GooglePlayInternalAndTestFlight`를 사용합니다.

Android 요청에서는 `BuildSettingsSO.keyStoreAlias` 값을 `androidKeyaliasName`으로 함께 저장합니다. 기본 운영 방식에서는 keystore password와 alias password를 GitHub Actions Secrets에서 주입하고, 실험용 request override가 있을 때만 request 값을 우선 사용합니다.

Android package name은 `BuildSettingsSO.androidPackageName`, iOS bundle id는 `BuildSettingsSO.iosPackageName` 값을 request에 함께 저장합니다. workflow는 이 request 값을 Google Play `packageName`과 TestFlight `app_identifier`로 사용하므로, profile별 package/bundle id를 workflow env에 따로 적지 않습니다.

실험용으로 Android keystore password, alias password, Google Play service account JSON, App Store Connect API key, iOS development team id도 request에 저장할 수 있습니다. Google Play service account JSON과 App Store Connect API key id, issuer id, P8 입력값은 `BuildSettingsSO`에 임시 저장됩니다. 이 값들은 `.build/build_request.json` 커밋 히스토리에 남으므로 일반 운영 빌드에서는 GitHub Actions Secrets/env 사용을 권장합니다.

`Distribution Profile`은 배포 계정 선택값입니다. BuildCommit은 `Actionfit` 또는 `Stormborn`을 `distributionProfile`로 request에 저장하고, workflow는 이 값으로 Google Play/App Store Connect credential fallback 묶음을 선택합니다.

## CI Build

원격 빌드머신은 BuildCommit이 태그로 지정한 저장 커밋에서 `.build/build_request.json`을 읽어 같은 `BuildSettingsSO` 기반 빌드를 재현합니다. `CIBuildEntry`는 request의 `triggerSource`가 `BuildCommit`인 경우만 처리합니다.

```bash
Unity -batchmode -quit -projectPath . -executeMethod ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest
```

기본 GitHub Actions workflow template은 `WorkflowTemplates/buildcommit-auto-build.yml`에 있습니다. 프로젝트에서 사용하려면 내용을 `.github/workflows/buildcommit-auto-build.yml`로 복사한 뒤, Unity/Xcode 경로와 iOS team id 같은 프로젝트별 env 값을 조정합니다.

workflow는 macOS self-hosted runner 기준입니다. runner에는 `self-hosted`, `macOS`, `unity-mobile` 라벨이 있어야 하며, 같은 Mac에서 Unity CLI로 Android/iOS를 빌드합니다. `Platform=Both` 요청은 workflow가 Android job과 iOS job으로 나눠 `.build/build_request.json`의 platform 값을 임시 변환한 뒤 `CIBuildEntry.BuildFromRequest`를 각각 호출합니다.

Android signing 비밀번호와 Google Play service account는 기본적으로 공통 `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_PASS`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`을 사용합니다. request에 실험용 override 값이 있으면 workflow가 request 값을 우선 사용하고, 없으면 Secrets/env로 fallback합니다. App Store Connect secret도 profile별 `ACTIONFIT_*`, `STORMBORN_*` 값을 기본으로 사용하며 request override가 있으면 우선 적용합니다.

상세 Mac 서버 준비 절차는 [MAC_SELF_HOSTED_RUNNER_SETUP.md](MAC_SELF_HOSTED_RUNNER_SETUP.md)를 참고합니다.

## 의존성

- `com.actionfit.buildsetting@1.1.1` 이상
- Unity `6000.2`
- Android/iOS 빌드용 Unity modules
- GitHub Actions self-hosted macOS runner

Build Automation은 `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, `iOSBuildProcess`를 Build Setting 패키지에서 사용합니다.
