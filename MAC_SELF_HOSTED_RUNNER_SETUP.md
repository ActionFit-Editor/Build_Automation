# Mac Self-hosted Runner Setup

이 문서는 `BuildCommit Auto Build` workflow를 실행할 Mac 서버를 준비하는 절차입니다. 대상 workflow는 `.github/workflows/buildcommit-auto-build.yml`이며, Android와 iOS 모두 같은 macOS self-hosted runner에서 Unity CLI로 빌드합니다.

## 1. 목표 상태

Mac 서버는 아래 조건을 만족해야 합니다.

- GitHub Actions self-hosted runner가 등록되어 있고 `unity-mobile` 라벨이 붙어 있음
- runner를 실행하는 macOS 사용자 계정에서 Unity `6000.2.6f2` 라이선스가 활성화되어 있음
- Unity Android/iOS build support가 설치되어 있음
- Xcode signing으로 App Store용 archive/export가 가능함
- Android keystore, Google Play service account, App Store Connect API key, iOS keychain password가 Mac 로컬 시크릿 번들에 저장되어 있음

## 2. Mac 기본 설정

Mac이 빌드 중 잠자기에 들어가면 job이 실패합니다.

```bash
sudo pmset -a sleep 0 disksleep 0 displaysleep 30
```

Xcode와 command line tools를 활성화합니다.

```bash
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -version
```

Homebrew가 없다면 먼저 설치한 뒤, 기본 CLI 도구를 설치합니다.

```bash
brew install git git-lfs ruby
git lfs install --system

gem install bundler fastlane
fastlane --version
```

Apple Silicon Mac에서는 Homebrew 경로가 보통 `/opt/homebrew/bin`입니다. runner 서비스에서 `fastlane`을 못 찾는 경우가 있으므로, runner 사용자 계정에서 아래 명령이 모두 성공하는지 확인합니다.

```bash
which git
which git-lfs
which ruby
which fastlane
```

## 3. Unity 설치

Unity Hub에서 Unity `6000.2.6f2`를 설치합니다.

필수 모듈:

- Android Build Support
- Android SDK & NDK Tools
- OpenJDK
- iOS Build Support

workflow는 Unity 실행 파일을 아래 경로로 찾습니다.

```bash
/Applications/Unity/Hub/Editor/6000.2.6f2/Unity.app/Contents/MacOS/Unity
```

설치 후 runner 사용자 계정에서 한 번 프로젝트를 열어 Unity 라이선스와 패키지 import가 정상인지 확인합니다.

```bash
/Applications/Unity/Hub/Editor/6000.2.6f2/Unity.app/Contents/MacOS/Unity \
  -batchmode \
  -quit \
  -projectPath /path/to/Cat_Merge_Cafe \
  -logFile /tmp/cat-merge-unity-open.log
```

`No valid Unity Editor license` 로그가 나오면 Unity Hub에서 같은 macOS 사용자 계정으로 로그인하고 라이선스를 활성화해야 합니다.

## 4. GitHub self-hosted runner 등록

GitHub repository에서 runner 등록 명령을 발급합니다.

경로:

```text
Settings > Actions > Runners > New self-hosted runner > macOS
```

GitHub 화면에 표시되는 다운로드 명령을 Mac에서 그대로 실행합니다. 등록 단계에서는 라벨에 `unity-mobile`을 추가합니다.

```bash
./config.sh \
  --url https://github.com/ActionFitGames/Cat_Merge_Cafe \
  --token <GitHub 화면에서 발급된 토큰> \
  --name cat-merge-mac-01 \
  --labels unity-mobile \
  --work _work
```

`self-hosted`, `macOS`, architecture 라벨은 GitHub runner가 자동으로 붙입니다. workflow는 `[self-hosted, macOS, unity-mobile]` 조합으로 이 Mac을 선택합니다.

먼저 foreground 실행으로 연결을 확인합니다.

```bash
./run.sh
```

GitHub Actions 화면에서 runner가 `Idle`로 보이면 정상입니다.

상시 실행이 필요하면 service로 등록합니다.

```bash
./svc.sh install
./svc.sh start
./svc.sh status
```

runner service는 반드시 Unity 라이선스를 활성화한 같은 macOS 사용자 계정에서 설치합니다.

## 5. iOS signing 준비

TestFlight 업로드에는 Apple Distribution 인증서와 App Store provisioning profile이 필요합니다.

workflow는 runner에 미리 설치된 login keychain 상태를 전제로 하지 않습니다. 로컬 시크릿 번들의 profile별 `.p12`를 임시 keychain에 import하고, profile별 `.mobileprovision`을 설치한 뒤 manual App Store signing으로 `.ipa`를 export합니다.

준비할 파일:

- Apple Distribution 인증서와 private key가 들어 있는 `.p12`
- 같은 Apple Distribution 인증서를 포함하는 App Store provisioning profile `.mobileprovision`
- App Store Connect API key `.p8`

이 프로젝트의 기본 Actionfit Team ID는 `49W7A8489P`입니다. workflow는 BuildCommit의 `Distribution Profile`에 따라 로컬 시크릿 번들의 `profiles/<profile>/profile.env`에서 `IOS_DEVELOPMENT_TEAM_ID`를 읽고, 이 값을 `xcodebuild`의 `DEVELOPMENT_TEAM`으로 넘깁니다.
`.p12`도 같은 Team ID의 Apple Distribution identity여야 합니다. 예를 들어 Actionfit 빌드는 `Apple Distribution: ACTIONFIT Ltd. (49W7A8489P)` identity와 private key가 들어 있는 `.p12`를 사용해야 합니다.

App Store Connect API key는 TestFlight upload에 사용됩니다. signing/export는 로컬 `.p12`와 `.mobileprovision`으로 처리하므로 Mac Studio로 이전할 때도 같은 로컬 시크릿 번들을 옮기면 됩니다.

## 6. 로컬 시크릿 번들 준비

self-hosted runner는 회사 credential을 GitHub Secrets가 아니라 Mac 로컬 파일에서 읽습니다. 기준 경로는 `.github/workflows/buildcommit-auto-build.yml`의 `CI_SECRET_ROOT`이고, 현재 yml 값은 `/Users/actionfit/ci-secrets/build-automation`입니다. BuildCommit request에는 runner 로컬 경로를 넣지 않습니다.

기본값:

```bash
$HOME/ci-secrets/build-automation
```

runner를 실행하는 macOS 사용자 계정에서 템플릿을 생성합니다.

```bash
cd /path/to/Cat_Merge_Cafe
bash Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh \
  "$HOME/ci-secrets/build-automation"
```

생성되는 구조:

```text
ci-secrets/build-automation/
  shared/
    android-signing.env
    ios-keychain.env
  profiles/
    actionfit/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Actionfit.p8
        AppleDistribution_Actionfit.p12
        profiles/
          com.actionfit.catmerge.ios.mobileprovision
    stormborn/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Stormborn.p8
        AppleDistribution_Stormborn.p12
        profiles/
          com.stormborn.example.ios.mobileprovision
```

공통 Android 비밀번호 fallback은 `shared/android-signing.env`에 넣습니다.

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

새 AutoBuild 요청은 `BuildSettingsSO.keystorePassword`, `BuildSettingsSO.aliasPassword`를 `.build/build_request.json`에 자동 저장하므로 일반적으로 이 fallback 값은 비워도 됩니다. request에 비밀번호가 없거나 수동 request를 실행할 때만 사용됩니다.

프로필별로 Android 비밀번호가 다르면 `profiles/<profile>/android-signing.env`에서 덮어씁니다.

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

workflow는 `shared/android-signing.env`를 먼저 읽고 `profiles/<profile>/android-signing.env`를 나중에 읽습니다. 따라서 프로필별 fallback 파일에 값이 있으면 그 값이 우선입니다. 단, Unity 빌드 단계에서는 AutoBuild request에 저장된 Android 비밀번호가 있으면 그 값이 fallback env보다 우선입니다.

공통 iOS keychain 정보는 선택 사항입니다. 일반적으로 비워둡니다.

```bash
IOS_KEYCHAIN_PASSWORD=""
IOS_KEYCHAIN_PATH=""
```

둘 다 비워두면 workflow가 run마다 임시 keychain을 만들고, profile별 `.p12`를 import한 뒤 cleanup에서 삭제합니다. 특정 persistent keychain을 써야 할 때만 두 값을 채웁니다.

회사별 `profile.env`에는 실제 파일 경로와 iOS/App Store Connect 값을 넣습니다.

```bash
ANDROID_KEYSTORE_PATH="$HOME/ci-secrets/build-automation/profiles/actionfit/android/upload.keystore"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$HOME/ci-secrets/build-automation/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="$HOME/ci-secrets/build-automation/profiles/actionfit/ios/AuthKey_Actionfit.p8"
IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="$HOME/ci-secrets/build-automation/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD="..."
IOS_APP_STORE_PROVISIONING_PROFILE_DIR="$HOME/ci-secrets/build-automation/profiles/actionfit/ios/profiles"
IOS_PROVISIONING_PROFILE_AUTO_GENERATE="true"
```

이 service account가 Actionfit/Stormborn 양쪽 Play Console 앱에 업로드 권한을 가져야 합니다. Google Play `packageName`은 AutoBuild request의 `androidPackageName` 값을 사용하며, 이 값은 BuildSetting의 `BuildSettingsSO.androidPackageName`에서 옵니다.

Android keystore 파일, alias 이름, signing 비밀번호는 새 AutoBuild request가 BuildSetting의 `BuildSettingsSO.keyStorePath`, `BuildSettingsSO.keyStoreAlias`, `BuildSettingsSO.keystorePassword`, `BuildSettingsSO.aliasPassword` 값에서 전달합니다. keystore 파일은 `androidKeystoreBase64`로 직렬화됩니다. 로컬 시크릿 번들의 `ANDROID_KEYSTORE_PATH`와 Android 비밀번호 env는 request에 값이 없는 수동/legacy 요청용 fallback입니다.

Android package name과 iOS bundle id도 로컬 시크릿이나 workflow env에 넣지 않습니다. AutoBuild request가 BuildSetting의 `BuildSettingsSO.androidPackageName`, `BuildSettingsSO.iosPackageName` 값을 전달하고, workflow는 이 값을 Google Play `packageName`, TestFlight `app_identifier`, 그리고 `ios/profiles/<iosBundleId>.mobileprovision` 선택에 사용합니다.

권한을 잠급니다.

```bash
chmod -R go-rwx "$HOME/ci-secrets/build-automation"
find "$HOME/ci-secrets/build-automation" -type d -exec chmod 700 {} \;
find "$HOME/ci-secrets/build-automation" -type f -exec chmod 600 {} \;
```

검증 명령:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  actionfit Android GooglePlayInternal

bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  actionfit iOS TestFlight
```

더 자세한 로컬 시크릿 번들 설명은 [RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md](RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md)를 참고합니다. Mac Studio를 다른 AI가 세팅하거나 진단해야 할 때는 [RunnerSetup/AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md](RunnerSetup/AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md)를 먼저 읽게 하면 됩니다.

AutoBuild request의 `iosDevelopmentTeamId`가 있으면 workflow가 request 값을 우선 사용하고, 없으면 profile별 `profile.env`의 `IOS_DEVELOPMENT_TEAM_ID` 값으로 fallback합니다. Android package name과 iOS bundle id는 `Tools > ActionFit > BuildSetting > SettingWindow`에서 설정한 값을 AutoBuild request로 전달하므로 workflow 상단 env에 따로 추가하지 않습니다.

## 7. 첫 테스트 순서

처음부터 `Both`를 실행하지 말고 플랫폼별로 나눠 확인합니다.

1. Android 빌드만 테스트

```text
Tools > ActionFit > BuildSetting > AutoBuild
Platform = Android
Build Kind = AndroidAab
Upload Target = GooglePlayInternal
Commit, Tag & Push
```

확인할 것:

- `build/aos-play/...` 태그 push로 GitHub Actions가 시작되는지
- Android job이 macOS runner에서 시작되는지
- Unity가 Android target으로 열리는지
- `Builds/**/*.aab`가 생성되는지
- Google Play internal upload가 성공하는지

2. iOS 빌드만 테스트

```text
Tools > ActionFit > BuildSetting > AutoBuild
Platform = iOS
Build Kind = iOSXcodeProject
Upload Target = TestFlight
Commit, Tag & Push
```

확인할 것:

- `Builds/iOS` Xcode project가 생성되는지
- `xcodebuild archive`가 signing을 통과하는지
- `Builds/iOSExport/**/*.ipa`가 생성되는지
- TestFlight upload가 성공하는지

3. 양쪽 동시 요청 테스트

```text
Tools > ActionFit > BuildSetting > AutoBuild
Platform = Both
Upload Target = GooglePlayInternalAndTestFlight
Commit, Tag & Push
```

workflow는 `Both` 요청을 Android job과 iOS job으로 나누어 처리합니다. 두 job이 같은 Mac runner를 공유하면 동시에 실행되지 않고 큐에 쌓일 수 있습니다.

## 8. 자주 나는 오류

### runner가 job을 받지 않음

- GitHub Actions runner 목록에서 `Online`인지 확인
- runner 라벨에 `unity-mobile`이 있는지 확인
- workflow의 `runs-on: [self-hosted, macOS, unity-mobile]`와 라벨이 일치하는지 확인

### Unity executable not found

Unity가 아래 경로에 없으면 workflow가 바로 실패합니다.

```bash
/Applications/Unity/Hub/Editor/6000.2.6f2/Unity.app/Contents/MacOS/Unity
```

Unity Hub 설치 경로가 다르면 workflow의 `UNITY_EXECUTABLE` 값을 수정해야 합니다.

### No valid Unity Editor license

runner service 사용자와 Unity Hub 로그인 사용자가 다를 때 자주 발생합니다.

- runner service를 중지
- 같은 macOS 사용자 계정으로 Unity Hub 로그인
- Unity 라이선스 활성화
- runner service 재시작

```bash
./svc.sh stop
./svc.sh start
```

### fastlane command not found

service 환경의 `PATH`가 터미널과 다를 수 있습니다.

```bash
which fastlane
```

Apple Silicon Mac에서는 `/opt/homebrew/bin/fastlane`, Intel Mac에서는 `/usr/local/bin/fastlane`에 있는지 확인합니다. 필요하면 runner service를 재설치하거나 workflow에서 `PATH`에 Homebrew 경로를 추가합니다.

### iOS signing 실패

확인 항목:

- `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`가 실제 `.p12` 파일을 가리키는지
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`가 `.p12` export 비밀번호와 맞는지
- `.p12` 안의 Apple Distribution identity가 `IOS_DEVELOPMENT_TEAM_ID`와 같은 팀인지
- `IOS_APP_STORE_PROVISIONING_PROFILE_DIR/<iosBundleId>.mobileprovision` 파일이 있거나 `IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true`인지
- `.mobileprovision` 안에 위 `.p12`의 Apple Distribution 인증서가 포함되어 있는지

### Google Play upload 실패

확인 항목:

- 로컬 시크릿 번들의 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`가 실제 JSON 파일을 가리키는지
- Play Console에서 service account에 internal track release 권한이 있는지
- 첫 릴리스가 Play Console에서 한 번 수동 업로드된 적이 있는지
- Build Kind가 `AndroidAab`인지

## 9. 참고 문서

- GitHub self-hosted runner 추가: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners
- GitHub runner service 설정: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service
- fastlane TestFlight upload: https://docs.fastlane.tools/actions/pilot/
- Google Play upload action: https://github.com/r0adkll/upload-google-play
