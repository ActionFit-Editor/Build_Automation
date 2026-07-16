# Mac Self-hosted Runner Setup

이 문서는 `BuildCommit Auto Build` workflow를 실행할 Mac 서버를 준비하는 절차입니다. 대상 workflow는 `.github/workflows/buildcommit-auto-build.yml`이며, Android와 iOS 모두 같은 macOS self-hosted runner에서 Unity CLI로 빌드합니다.

## 1. 목표 상태

Mac 서버는 아래 조건을 만족해야 합니다.

- GitHub Actions self-hosted runner가 등록되어 있고 `unity-mobile` 라벨이 붙어 있음
- runner를 실행하는 macOS 사용자 계정에서 `$UNITY_PROJECT_DIR/ProjectSettings/ProjectVersion.txt`의 `m_EditorVersion`에 해당하는 Unity 라이선스가 활성화되어 있음
- Unity Android/iOS build support가 설치되어 있음
- Xcode signing으로 App Store용 archive/export가 가능함
- Google Play service account, App Store Connect API key, iOS certificate/keychain 설정이 Mac 로컬 시크릿 번들에 저장되어 있고, Android request fallback을 사용할 경우에만 Android keystore와 signing 비밀번호도 준비되어 있음

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

Unity Hub에서 대상 Unity 프로젝트의 `ProjectSettings/ProjectVersion.txt`에 적힌 `m_EditorVersion` 버전을 설치합니다. Workflow와 BuildRequest는 Git 저장소 루트에 있어도 Unity 프로젝트는 저장소 루트 또는 `KnitFactory` 같은 하위 디렉터리에 있을 수 있습니다.

필수 모듈:

- Android Build Support
- Android SDK & NDK Tools
- OpenJDK
- iOS Build Support

workflow는 `UNITY_HUB_EDITOR_ROOT` 아래에서 `m_EditorVersion`과 일치하는 Unity 실행 파일을 찾습니다.

```bash
/Applications/Unity/Hub/Editor/<m_EditorVersion>/Unity.app/Contents/MacOS/Unity
```

설치 후 runner 사용자 계정에서 한 번 프로젝트를 열어 Unity 라이선스와 패키지 import가 정상인지 확인합니다.

```bash
REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
UNITY_PROJECT_PATH="KnitFactory" # Use "." for a repository-root Unity project.
UNITY_PROJECT_DIR="$REPOSITORY_ROOT/$UNITY_PROJECT_PATH"
UNITY_VERSION="$(sed -n 's/^m_EditorVersion:[[:space:]]*//p' "$UNITY_PROJECT_DIR/ProjectSettings/ProjectVersion.txt" | head -n 1)"
"/Applications/Unity/Hub/Editor/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity" \
  -batchmode \
  -quit \
  -projectPath "$UNITY_PROJECT_DIR" \
  -logFile /tmp/buildcommit-unity-open.log
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
  --url https://github.com/<OWNER>/<REPO> \
  --token <GitHub 화면에서 발급된 토큰> \
  --name actionfit-mac-01 \
  --labels unity-mobile \
  --work _work
```

`self-hosted`, `macOS`, architecture 라벨은 GitHub runner가 자동으로 붙입니다. BuildCommit workflow의 `allocate` job은 프로젝트별 `project-*` affinity 라벨을 추가합니다. 저장소 Actions variable `UNITY_RUNNER_AFFINITY_LABEL`에 라벨(예: `project-cat-merge-cafe`)을 설정할 수 있으며, 생략하면 repository 이름으로 같은 형식의 라벨을 자동 생성합니다.

`allocate` job은 모바일 빌드 runner와 분리된 전용 runner에서 실행합니다. 조직 runner group은 `mobile-build-allocator`, custom label은 `runner-allocator`를 사용하고, BuildCommit을 허용할 private repository만 이 group에 연결합니다. 해당 Mac에는 `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner`가 실행 가능 상태로 있어야 하며, 같은 사용자 계정의 `gh` Keychain 인증이 조직 runner 조회/라벨 추가 권한을 가져야 합니다. workflow는 Actions secret `UNITY_RUNNER_ALLOCATOR_TOKEN`을 사용하지 않습니다.

host-local allocator는 전역 lock을 잡고 기존 프로젝트 라벨이 붙은 online `unity-mobile` runner를 재사용합니다. 매핑이 없으면 `ci`, `ci-validation`, `unity-package-ci`, `runner-allocator`가 없는 online runner 중 `project-*` 라벨 수가 가장 적은 Mac을 선택하며, 동률일 때 idle runner를 우선합니다. workflow의 `mobile-build` job은 allocator output과 `self-hosted`, `macOS`, `unity-mobile` 조합으로 이 Mac을 선택합니다.

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

self-hosted Unity runner는 Android BuildRequest의 keystore Base64와 signing 비밀번호를 우선 사용하고, 누락된 Android 값 및 Google Play/iOS/App Store Connect/Slack credential은 공유 runner bundle에서 읽습니다. Mac Studio runner는 `/Users/lydia/workspace/build-automation`, MacBook runner는 Mac Studio SMB 공유의 고정 mountpoint를 `CI_SECRET_ROOT`로 설정합니다. workflow resolver는 runner 환경을 우선하며 `/Volumes/ActionFitBuildAutomation`을 fallback으로 지원합니다. BuildCommit request에는 runner 로컬 경로나 Slack credential을 넣지 않습니다.

기본 workflow template 경로:

```bash
/Users/lydia/workspace/build-automation
```

각 runner 설치 디렉터리의 `.env`에 host별 경로를 지정하고 서비스를 재시작합니다.

```bash
# Mac Studio build runners
CI_SECRET_ROOT=/Users/lydia/workspace/build-automation

# MacBook build runners: replace with the fixed SMB automount path
CI_SECRET_ROOT=/path/to/ActionFitBuildAutomation
```

Finder에서 수동 연결한 `/Volumes/ActionFitBuildAutomation`은 재연결 시 suffix가 붙거나 로그인 전 service에서 보이지 않을 수 있으므로 운영 기본값이 아니라 fallback으로만 사용합니다.

runner를 실행하는 macOS 사용자 계정에서 템플릿을 생성합니다.

```bash
cd /path/to/GitRepository
REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
UNITY_PROJECT_PATH="KnitFactory" # Use "." for a repository-root Unity project.
UNITY_PROJECT_DIR="$REPOSITORY_ROOT/$UNITY_PROJECT_PATH"
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh" \
  "/Users/lydia/workspace/build-automation"
```

생성되는 구조:

```text
workspace/build-automation/
  shared/
    android-signing.env
    ios-keychain.env
    github-package-read-token
    slack-webhook-url
    slack-bot-token
    slack-channel-id
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

공통 Android signing 비밀번호는 `shared/android-signing.env`에 넣습니다.

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

두 값은 schema 12 BuildRequest에 해당 signing 비밀번호가 없을 때 사용하는 fallback입니다.

프로필별로 Android 비밀번호가 다르면 `profiles/<profile>/android-signing.env`에서 덮어씁니다.

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

workflow는 `shared/android-signing.env`를 먼저 읽고 `profiles/<profile>/android-signing.env`를 나중에 읽습니다. Request에 해당 비밀번호가 없어서 runner fallback을 사용할 때는 프로필별 파일의 값이 공통 파일보다 우선합니다.

공통 iOS keychain 정보는 선택 사항입니다. 일반적으로 비워둡니다.

```bash
IOS_KEYCHAIN_PASSWORD=""
IOS_KEYCHAIN_PATH=""
```

둘 다 비워두면 workflow가 run마다 임시 keychain을 만들고, profile별 `.p12`를 import한 뒤 cleanup에서 삭제합니다. 특정 persistent keychain을 써야 할 때만 두 값을 채웁니다.

private GitHub UPM package 접근은 runner 사용자 계정의 `gh auth`를 우선 사용합니다.

```bash
gh auth status --hostname github.com
gh auth setup-git --hostname github.com
```

`gh auth`를 사용할 수 없는 runner라면 `shared/github-package-read-token` 파일의 첫 non-comment line에 private ActionFit package repo read 권한이 있는 fine-grained token을 넣습니다. workflow는 Unity 실행 전에 이 credential을 준비하고 `$UNITY_PROJECT_DIR/Packages/manifest.json`의 ActionFit GitHub package 접근을 `git ls-remote`로 사전 확인합니다.

Slack 알림과 Development APK 전송은 성공한 `mobile-build` job이 직접 수행합니다. `shared/slack-webhook-url`은 시작/실패 알림, `shared/slack-bot-token`과 `shared/slack-channel-id`는 APK 파일 게시에 사용합니다. Android가 먼저 끝난 Both 요청도 iOS와 지연 Store 업로드가 모두 성공한 뒤 APK를 전송하며, 성공 메시지는 APK 게시물에 포함됩니다. Slack 실패는 빌드 결과를 바꾸지 않고 `BUILD SUCCESS / APK DELIVERY FAILED` 경고를 시도합니다.

Slack 사람 태그는 AutoBuild 창의 `Slack Mentions` 행 목록에서 설정합니다. 각 행은 `Mention` 체크박스, `Member ID`, `Memo`를 가지며 BuildAutomation 패키지의 `BuildAutomationSettingsSO`에 저장되어 프로젝트에서 공유됩니다. 기본 에셋 경로는 `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`입니다. `Mention`이 체크된 행의 `Member ID`만 `.build/build_request.json`의 `slackMentions` JSON 배열로 직렬화되어 mobile build workflow에 전달됩니다. `Memo`는 request에 포함되지 않고 AutoBuild 창에서 식별용으로 보입니다. 표시 이름이나 Slack markup이 아니라 raw `U12345678` 또는 `W12345678` 형식만 사용합니다.

회사별 `profile.env`에는 실제 파일 경로와 iOS/App Store Connect 값을 넣습니다.

```bash
ANDROID_KEYSTORE_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/upload.keystore"
# Optional: overrides the request's non-secret Android alias metadata.
# ANDROID_KEYALIAS_NAME="upload"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AuthKey_Actionfit.p8"
IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD="..."
IOS_APP_STORE_PROVISIONING_PROFILE_DIR="${CI_SECRET_ROOT}/profiles/actionfit/ios/profiles"
IOS_PROVISIONING_PROFILE_AUTO_GENERATE="true"
```

이 service account가 Actionfit/Stormborn 양쪽 Play Console 앱에 업로드 권한을 가져야 합니다. Google Play `packageName`은 AutoBuild request의 `androidPackageName` 값을 사용하며, 이 값은 BuildSetting의 `BuildSettingsSO.androidPackageName`에서 옵니다.

Android keystore 파일과 signing 비밀번호는 AutoBuild request의 `androidKeystoreBase64`, `androidKeystorePassword`, `androidAliasPassword`를 우선 사용합니다. 누락된 값만 runner 로컬 `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_PASS`에서 fallback합니다. Alias는 AutoBuild request의 `androidKeyaliasName`을 사용합니다.

Android package name과 iOS bundle id도 로컬 시크릿이나 workflow env에 넣지 않습니다. AutoBuild request가 BuildSetting의 `BuildSettingsSO.androidPackageName`, `BuildSettingsSO.iosPackageName` 값을 전달하고, workflow는 이 값을 Google Play `packageName`, TestFlight `app_identifier`, 그리고 `ios/profiles/<iosBundleId>.mobileprovision` 선택에 사용합니다.

권한을 잠급니다.

```bash
chmod -R go-rwx "/Users/lydia/workspace/build-automation"
find "/Users/lydia/workspace/build-automation" -type d -exec chmod 700 {} \;
find "/Users/lydia/workspace/build-automation" -type f -exec chmod 600 {} \;
```

검증 명령:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  actionfit Android GooglePlayInternal

bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  actionfit iOS TestFlight
```

더 자세한 로컬 시크릿 번들 설명은 [RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md](RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md)를 참고합니다. Mac Studio를 다른 AI가 세팅하거나 진단해야 할 때는 [RunnerSetup/AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md](RunnerSetup/AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md)를 먼저 읽게 하면 됩니다.

`IOS_DEVELOPMENT_TEAM_ID`는 profile별 `profile.env`에서만 읽습니다. Android package name과 iOS bundle id는 `Tools > Package > Build Setting > Setting Window`에서 설정한 값을 AutoBuild request로 전달하므로 workflow 상단 env에 따로 추가하지 않습니다.

Schema 11의 `unityProjectPath`는 Git 저장소 루트 기준 상대경로입니다. Workflow/scripts와 `.build/build_request.json`은 항상 저장소 루트에 있고, `Packages`, `ProjectSettings`, `Library`, `Builds`, `Logs`는 resolve된 `$UNITY_PROJECT_DIR` 기준입니다. `autoConfigureBuildSymbols=true`이면 target switch Unity 프로세스가 Custom Symbols의 platform/Build 체크 결과를 적용하고, 별도 build 프로세스가 같은 심볼 목록을 검증합니다.

## 7. 첫 테스트 순서

처음부터 `Both`를 실행하지 말고 플랫폼별로 나눠 확인합니다.

1. Android 빌드만 테스트

```text
Tools > Package > Build Automation > AutoBuild
Platform = Android
Build Kind = AndroidAab
Upload Target = GooglePlayInternal
Commit, Tag & Push
```

확인할 것:

- `build/aos-play/...` 태그 push로 GitHub Actions가 시작되는지
- Android phase가 affinity macOS runner에서 시작되는지
- Unity가 Android target으로 열리는지
- `$UNITY_PROJECT_DIR/Builds/**/*.aab`가 생성되는지
- Google Play internal upload가 성공하는지

2. iOS 빌드만 테스트

```text
Tools > Package > Build Automation > AutoBuild
Platform = iOS
Build Kind = iOSXcodeProject
Upload Target = TestFlight
Commit, Tag & Push
```

확인할 것:

- `$UNITY_PROJECT_DIR/Builds/iOS` Xcode project가 생성되는지
- `xcodebuild archive`가 signing을 통과하는지
- `$UNITY_PROJECT_DIR/Builds/iOSExport/**/*.ipa`가 생성되는지
- TestFlight upload가 성공하는지

3. 양쪽 동시 요청 테스트

```text
Tools > Package > Build Automation > AutoBuild
Platform = Both
Upload Target = GooglePlayInternalAndTestFlight
Commit, Tag & Push
```

workflow는 `Both` 요청을 하나의 `mobile-build` job에서 순차 처리합니다. 현재 target이 Android면 Android → iOS, iOS면 iOS → Android 순서이며 다른 target이면 Android → iOS 순서입니다. 두 플랫폼은 같은 affinity runner와 `Library`를 사용하고 플랫폼 전환은 1회만 수행합니다.

## 8. 자주 나는 오류

### runner가 job을 받지 않음

- `haneul-ui-Mac-Studio-allocator`가 `mobile-build-allocator` group과 `runner-allocator` label로 online인지 확인
- `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner`가 실행 가능하고 allocator 사용자 `gh` 인증에 조직 runner write 권한이 있는지 확인
- GitHub Actions runner 목록에서 `Online`인지 확인
- runner 라벨에 `unity-mobile`이 있는지 확인
- 저장소 variable `UNITY_RUNNER_AFFINITY_LABEL`을 사용했다면 값이 `project-*` 형식인지 확인
- allocator output의 affinity 라벨과 runner에 추가된 라벨이 일치하는지 확인

### Unity executable not found

`$UNITY_PROJECT_DIR/ProjectSettings/ProjectVersion.txt`의 `m_EditorVersion`과 일치하는 Unity가 아래 경로에 없으면 workflow가 바로 실패합니다.

```bash
/Applications/Unity/Hub/Editor/<m_EditorVersion>/Unity.app/Contents/MacOS/Unity
```

Unity Hub 설치 루트가 다르면 workflow의 `UNITY_HUB_EDITOR_ROOT` 값을 수정해야 합니다.

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
