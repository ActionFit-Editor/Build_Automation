# Mac Self-hosted Runner Setup

이 문서는 `BuildCommit Auto Build` workflow를 실행할 Mac 서버를 준비하는 절차입니다. 대상 workflow는 `.github/workflows/buildcommit-auto-build.yml`이며, Android와 iOS 모두 같은 macOS self-hosted runner에서 Unity CLI로 빌드합니다.

## 1. 목표 상태

Mac 서버는 아래 조건을 만족해야 합니다.

- GitHub Actions self-hosted runner가 등록되어 있고 `unity-mobile` 라벨이 붙어 있음
- runner를 실행하는 macOS 사용자 계정에서 Unity `6000.2.6f2` 라이선스가 활성화되어 있음
- Unity Android/iOS build support가 설치되어 있음
- Xcode signing으로 App Store용 archive/export가 가능함
- Android keystore secret, Google Play service account, App Store Connect API key가 GitHub Secrets에 등록되어 있음

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

TestFlight 업로드에는 App Store Distribution signing이 필요합니다.

Mac keychain에 Apple Distribution 인증서를 설치합니다.

- `Keychain Access`에서 Apple Distribution 인증서와 private key가 같이 보여야 함
- 인증서 trust 설정은 기본값 사용
- runner service가 접근할 수 있는 login keychain에 설치

Xcode에서 Apple account와 team 접근도 확인합니다.

```text
Xcode > Settings > Accounts
```

이 프로젝트의 기본 Actionfit Team ID는 `49W7A8489P`입니다. workflow는 BuildCommit의 `Distribution Profile`에 따라 `ACTIONFIT_IOS_DEVELOPMENT_TEAM_ID` 또는 `STORMBORN_IOS_DEVELOPMENT_TEAM_ID`를 `xcodebuild`의 `DEVELOPMENT_TEAM`으로 넘깁니다.

자동 provisioning을 쓰므로 App Store Connect API key에 profile 생성/갱신 권한이 필요합니다. 권한 문제가 있으면 `xcodebuild` 단계에서 signing 또는 provisioning profile 오류가 납니다.

## 6. GitHub Secrets 등록

GitHub repository의 아래 경로에서 Secrets를 등록합니다.

```text
Settings > Secrets and variables > Actions > Repository secrets
```

Actionfit Android:

- `ACTIONFIT_ANDROID_KEYSTORE_PASS`
- `ACTIONFIT_ANDROID_KEYALIAS_PASS`
- `ACTIONFIT_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

기존 설정과 호환하려면 Actionfit은 아래 unprefixed secrets도 fallback으로 사용할 수 있습니다.

- `ANDROID_KEYSTORE_PASS`
- `ANDROID_KEYALIAS_PASS`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

Stormborn Android:

- `STORMBORN_ANDROID_KEYSTORE_PASS`
- `STORMBORN_ANDROID_KEYALIAS_PASS`
- `STORMBORN_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

Android alias 이름은 secret으로 넣지 않습니다. BuildCommit request가 BuildSetting의 `BuildSettingsSO.keyStoreAlias` 값을 `androidKeyaliasName`으로 전달하고, workflow는 secret에 저장된 비밀번호만 주입합니다.

Actionfit iOS/TestFlight:

- `ACTIONFIT_APP_STORE_CONNECT_API_KEY_ID`
- `ACTIONFIT_APP_STORE_CONNECT_ISSUER_ID`
- `ACTIONFIT_APP_STORE_CONNECT_API_KEY_P8`

기존 설정과 호환하려면 Actionfit은 아래 unprefixed secrets도 fallback으로 사용할 수 있습니다.

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`

Stormborn iOS/TestFlight:

- `STORMBORN_APP_STORE_CONNECT_API_KEY_ID`
- `STORMBORN_APP_STORE_CONNECT_ISSUER_ID`
- `STORMBORN_APP_STORE_CONNECT_API_KEY_P8`

`*_APP_STORE_CONNECT_API_KEY_P8`은 `.p8` 파일 내용을 그대로 넣습니다. 줄바꿈이 `\n` 문자로 들어가도 workflow가 실제 줄바꿈으로 변환합니다.

또한 workflow 상단 env에서 profile별 공개 설정을 채워야 합니다.

- `ACTIONFIT_ANDROID_PACKAGE_NAME`
- `ACTIONFIT_IOS_BUNDLE_ID`
- `ACTIONFIT_IOS_DEVELOPMENT_TEAM_ID`
- `STORMBORN_ANDROID_PACKAGE_NAME`
- `STORMBORN_IOS_BUNDLE_ID`
- `STORMBORN_IOS_DEVELOPMENT_TEAM_ID`

## 7. 첫 테스트 순서

처음부터 `Both`를 실행하지 말고 플랫폼별로 나눠 확인합니다.

1. Android 빌드만 테스트

```text
Tools > ActionFit > Build Commit
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
Tools > ActionFit > Build Commit
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
Tools > ActionFit > Build Commit
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

- Apple Distribution 인증서와 private key가 login keychain에 있는지
- Xcode account가 선택한 profile의 Team ID에 접근 가능한지
- App Store Connect API key가 provisioning 갱신 권한을 가지는지
- 선택한 profile의 bundle id로 App Store profile이 생성 가능한지

### Google Play upload 실패

확인 항목:

- 선택한 profile의 `*_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` 값이 JSON 원문인지
- Play Console에서 service account에 internal track release 권한이 있는지
- 첫 릴리스가 Play Console에서 한 번 수동 업로드된 적이 있는지
- Build Kind가 `AndroidAab`인지

## 9. 참고 문서

- GitHub self-hosted runner 추가: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners
- GitHub runner service 설정: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service
- fastlane TestFlight upload: https://docs.fastlane.tools/actions/pilot/
- Google Play upload action: https://github.com/r0adkll/upload-google-play
