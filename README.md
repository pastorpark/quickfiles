# QuickFiles

QuickFiles는 macOS 메뉴 막대에서 실행되는 최근 파일 검색 유틸리티입니다. 전역 단축키로 작은 검색 패널을 열고, 지정한 폴더 안에서 최근 생성되거나 수정된 파일을 빠르게 찾고 열 수 있습니다.

## 주요 기능

- 메뉴 막대에서 상주하는 macOS 보조 앱
- 기본 단축키 `Command + Shift + /`로 QuickFiles 패널 열기
- 데스크톱, 다운로드, 문서 폴더의 최근 파일 자동 스캔
- 파일명과 상위 폴더 경로 기반 검색
- Quick Look 썸네일을 사용한 파일 미리보기
- 키보드 방향키로 항목 이동, `Enter`로 열기
- `Command + Enter` 또는 컨텍스트 메뉴로 Finder 위치 표시
- 파일 드래그, 복사, 다른 폴더로 이동
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

터미널에서 빌드하려면 다음 명령을 사용할 수 있습니다.

```sh
xcodebuild -project QuickFiles.xcodeproj -scheme QuickFiles -configuration Debug build
```

## 사용 방법

QuickFiles가 실행되면 Dock에는 표시되지 않고 메뉴 막대에만 나타납니다. 패널에서는 최근 파일이 가로 목록으로 표시되며, 검색어를 입력하면 파일 이름과 폴더 경로가 함께 검색됩니다.

- `←`, `→`: 이전/다음 항목 선택
- `↑`, `↓`: 여러 칸씩 이동
- `Enter`: 선택한 파일 열기
- `Command + Enter`: Finder에서 선택한 파일 위치 표시
- `Esc`: 패널 닫기
- 더블 클릭: 파일 열기
- 컨텍스트 메뉴: Finder 위치 표시, 열기, 복사
- `이동`: 선택한 파일을 다른 폴더로 이동

## 설정

설정 창은 메뉴 막대 아이콘의 `설정` 메뉴에서 열 수 있습니다.

### 일반

- 로그인 시 QuickFiles 자동 실행을 켜거나 끕니다.
- macOS에서 추가 승인이 필요한 경우 로그인 항목 설정을 열 수 있습니다.

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
  Services/
    SettingsStore.swift                  설정 저장과 복원
    RecentFileScanner.swift              최근 파일 스캔과 정렬
    FileSystemEventMonitor.swift         파일 시스템 변경 감시
    HotKeyController.swift               전역 단축키 등록
    LaunchAtLoginController.swift        로그인 시 자동 실행 관리
  UI/
    QuickAccessView.swift                검색 패널 UI
    PanelController.swift                패널 표시, 검색 결과 갱신, 파일 작업
    SettingsView.swift                   설정 화면
    SettingsWindowController.swift       설정 창 관리
  Assets.xcassets/                       앱 아이콘과 에셋
QuickFiles.xcodeproj/                    Xcode 프로젝트
```

## 구현 메모

- 파일 스캔은 숨김 파일과 패키지 내부를 건너뜁니다.
- 한 번의 폴더 스캔은 최대 10,000개 항목까지만 탐색합니다.
- 최근 파일 정렬 기준은 수정일, 생성일, 디렉터리 추가일, 메타데이터 변경일 중 가장 최신 값입니다.
- 검색 결과에는 설정한 최대 최근 파일 수만큼 표시되지만, 검색어 입력 시 전체 스캔 결과를 대상으로 필터링합니다.
- 파일 이동 시 같은 이름의 파일이 이미 있으면 `파일명 2`, `파일명 3` 형식으로 충돌을 피합니다.

## 라이선스

100% CODEX로 만들었습니다. 
