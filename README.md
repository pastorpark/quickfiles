# QuickFiles

QuickFiles는 macOS 메뉴 막대에서 실행되는 최근 파일 검색 유틸리티입니다. 전역 단축키로 작은 검색 패널을 열고, 지정한 폴더 안에서 최근 생성되거나 수정된 파일을 빠르게 찾고 열 수 있습니다.

## 주요 기능

- 메뉴 막대에서 상주하는 macOS 보조 앱
- 기본 단축키 `Command + Shift + /`로 QuickFiles 패널 열기
- 데스크톱, 다운로드, 문서 폴더의 최근 파일 자동 스캔
- 파일명과 상위 폴더 경로 기반 검색
- Quick Look 썸네일을 사용한 파일 미리보기, `Space`/`Command + Y`로 훑어보기(Quick Look)
- `Command`/`Shift` 클릭과 `Shift` + 방향키로 여러 파일 선택
- 선택한 파일 한꺼번에 열기, Finder에서 보기, 복사, 드래그, 다른 폴더로 이동
- 키보드 방향키로 항목 이동, `Enter`로 열기, `Command + Enter`로 Finder 위치 표시
- 한 줄에 6개씩 세로로 스크롤되는 파일 그리드, 높이를 조절할 수 있는 패널(크기 기억), 마우스가 있는 화면에 표시
- 자주 쓰는 파일과 폴더 북마크
- 검색 폴더, 제외 폴더, 제외 확장자 관리
- 로그인 시 자동 실행 설정
- 사용자 지정 전역 단축키 설정
- FSEvents 기반 파일 변경 감지와 자동 갱신

## 요구 사항

- macOS 13.0 이상
- Xcode
- Swift 5

## 실행 방법

1. Xcode에서 `QuickFiles.xcodeproj`를 엽니다.
2. `QuickFiles` scheme을 선택합니다.
3. Run을 실행합니다.
4. 메뉴 막대의 QuickFiles 아이콘을 클릭하거나 `Command + Shift + /`를 눌러 패널을 엽니다.

터미널에서 빌드하려면 다음 명령을 사용할 수 있습니다. 다중 선택 규칙 테스트는 저장소 루트에서 `swift test`로 실행합니다.

```sh
xcodebuild -project QuickFiles.xcodeproj -scheme QuickFiles -configuration Debug build
```

## 사용 방법

QuickFiles가 실행되면 Dock에는 표시되지 않고 메뉴 막대에만 나타납니다. 패널에서는 최근 파일이 한 줄에 6개씩 표시되고 아래로 스크롤되며, 검색어를 입력하면 파일 이름과 폴더 경로가 함께 검색됩니다. 북마크는 패널 아래쪽 줄에 표시됩니다. 패널의 위·아래 가장자리를 끌어 높이를 바꿀 수 있습니다.

**선택**

- 클릭: 하나만 선택
- `Command` + 클릭: 선택에 추가하거나 빼기
- `Shift` + 클릭: 범위 선택 (`Command + Shift` + 클릭은 범위를 추가)
- 더블 클릭: 클릭한 파일 열기
- 선택한 파일 중 하나를 끌면 선택한 파일 전체가 함께 드래그됩니다.

**키보드: 검색창에 커서가 있을 때**

- `↓`, `↑`: 다음/이전 파일 선택 (`Shift`를 누르면 범위 선택)
- `←`, `→`, `Command + A` 등: 검색어 편집
- `Tab`: 파일 목록으로 이동

**키보드: 파일 목록에 커서가 있을 때** (파일을 클릭하거나 `Tab`)

- `←`, `→`: 이전/다음 파일, `↑`, `↓`: 한 줄 위/아래(같은 열), 마지막 줄에서 `↓`는 북마크로 (`Shift`를 누르면 범위 선택)
- `Space`: 선택한 파일 훑어보기(Quick Look), 다시 누르면 닫기
- `Command + A`: 모두 선택, `Command + C`: 선택한 파일 복사
- `Tab`: 검색창으로 이동

**공통**

- `Command + Y`: 훑어보기 (검색창에 커서가 있어도 동작)
- `Enter`: 선택한 파일 모두 열기 (10개가 넘으면 확인)
- `Command + Enter`: 선택한 파일을 Finder에서 보기
- `Esc`: 여러 개가 선택되어 있으면 하나로 줄이고, 아니면 패널 닫기
- 컨텍스트 메뉴: 훑어보기, 열기, Finder에서 위치 보기, 복사, 이동, 북마크에 추가/제거 (선택한 파일 전체에 적용)
- `이동`: 선택한 파일을 다른 폴더로 이동 (이미 그 폴더에 있는 파일은 건너뜀)

## 설정

설정 창은 메뉴 막대 아이콘의 `설정` 메뉴에서 열 수 있습니다.

### 일반

- 로그인 시 QuickFiles 자동 실행을 켜거나 끕니다.
- macOS에서 추가 승인이 필요한 경우 로그인 항목 설정을 열 수 있습니다.
- 검색어가 없을 때 표시할 최근 파일 개수를 20~200개 사이에서 정합니다.

### 단축키

- 전역 단축키를 직접 녹화해 변경할 수 있습니다.
- 단축키에는 `Command`, `Option`, `Control`, `Shift` 중 하나 이상의 보조키가 필요합니다.
- macOS나 다른 앱에서 이미 사용 중인 단축키는 등록되지 않습니다.

### 검색

- 최근 파일을 찾을 폴더를 추가하거나 제거합니다.
- 기본 검색 폴더는 다음과 같습니다.
  - Desktop
  - Downloads
  - Documents

### 제외

- 검색에서 제외할 위치를 추가할 수 있습니다.
- 파일 확장자를 기준으로 제외할 수도 있습니다. 예를 들어 `jpg`, `mp3`, `zip` 등을 등록할 수 있습니다.
- 기본 제외 위치에는 시스템 폴더, 사용자 Library, 휴지통 등이 포함됩니다.

### 북마크

- 자주 쓰는 파일이나 폴더를 북마크로 저장합니다.
- 북마크는 QuickFiles 패널 하단에 별도로 표시됩니다.

## 데이터 저장 위치

사용자 설정은 다음 위치에 JSON 파일로 저장됩니다.

```text
~/Library/Application Support/QuickFiles/settings.json
```

검색 폴더와 북마크는 macOS 보안 범위 북마크 데이터와 함께 저장되어, 앱이 다시 실행된 뒤에도 선택한 위치를 다시 사용할 수 있습니다.

## 프로젝트 구조

```text
QuickFiles/
  QuickFilesApp.swift                    앱 진입점, 메뉴 막대 구성
  Models/
    AppModels.swift                      파일 항목, 북마크, 폴더 규칙, 단축키 모델
    SelectionModel.swift                 Finder 방식 다중 선택 규칙 (AppKit 의존 없음)
    MovePlanner.swift                    여러 파일 이동 계획 (건너뛸 항목, 함께 옮겨지는 항목)
    GridNavigation.swift                 그리드 위/아래 이동 규칙
  Services/
    SettingsStore.swift                  설정 저장과 복원
    RecentFileScanner.swift              최근 파일 스캔과 정렬
    FileSystemEventMonitor.swift         파일 시스템 변경 감시
    HotKeyController.swift               전역 단축키 등록
    LaunchAtLoginController.swift        로그인 시 자동 실행 관리
  UI/
    QuickAccessView.swift                검색 패널 UI, 키보드 처리
    PanelViewModel.swift                 검색 결과 캐시와 선택 상태
    TileInteractionView.swift            파일 타일의 클릭, 메뉴, 여러 파일 드래그 (AppKit)
    QuickPanelWindow.swift               패널 창, Quick Look 미리보기 제어
    PanelController.swift                패널 표시, 검색 결과 갱신, 여러 파일 작업
    SettingsView.swift                   설정 화면
    SettingsWindowController.swift       설정 창 관리
  Assets.xcassets/                       앱 아이콘, 메뉴 막대 아이콘 에셋
Design/AppIcon/                          아이콘 원본과 생성 스크립트
Tests/QuickFilesCoreTests/               선택·이동 계획·그리드 이동 단위 테스트
Package.swift                            테스트 실행용 Swift 패키지 (`swift test`)
QuickFiles.xcodeproj/                    Xcode 프로젝트
```

## 구현 메모

- 파일 스캔은 숨김 파일과 패키지 내부를 건너뜁니다.
- 한 번의 폴더 스캔은 최대 10,000개 항목까지만 탐색합니다.
- 최근 파일 정렬 기준은 수정일, 생성일, 디렉터리 추가일, 메타데이터 변경일 중 가장 최신 값입니다.
- 검색어가 없을 때는 최근 파일을 설정한 개수(기본 40개)만큼 표시합니다. 검색어 입력 시에는 전체 스캔 결과를 대상으로 필터링합니다.
- 파일 이동 시 같은 이름의 파일이 이미 있으면 `파일명 2`, `파일명 3` 형식으로 충돌을 피합니다.
- 현재 위치와 같은 폴더를 이동 대상으로 고르면 아무 작업도 하지 않습니다.
- 앱은 App Sandbox를 사용하지 않습니다. 북마크 데이터는 이동하거나 이름이 바뀐 항목을 다시 찾는 데 쓰이며, 오래된 북마크는 실행 시 자동으로 갱신됩니다.
- `settings.json`을 읽을 수 없으면 기본값으로 초기화하기 전에 같은 폴더에 `settings.backup-<날짜>.json`으로 백업합니다.

## 아이콘 출처

앱 아이콘과 메뉴 막대 아이콘은 Flaticon의 무료 아이콘을 사용합니다(무료 라이선스, 출처 표기 필수).

- <a href="https://www.flaticon.com/kr/free-icons/" title="종이 아이콘">종이 아이콘 제작자: Wyasa.Design - Flaticon</a>
- 원본: `Design/AppIcon/Source/flaticon-file-and-folder-9099437.png`
- 아이콘 다시 만들기: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift Design/AppIcon/compose_icon.swift`

## 라이선스

100% CODEX로 만들었습니다. 
