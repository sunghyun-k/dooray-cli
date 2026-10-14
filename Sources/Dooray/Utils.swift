import Foundation

/// 표준 에러로 메시지 출력 (stdout 본문 출력과 섞이지 않도록 경고/진단용)
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// 19자리 숫자 ID 패턴
nonisolated(unsafe) let doorayIdPattern = /^\d{19}$/

/// 두레이 URL 또는 식별자를 파싱하여 (projectId, postId) 또는 (projectCode, taskNumber)를 반환
enum TaskIdentifier: Sendable {
    case taskId(String)
    case projectAndTask(projectCode: String, taskNumber: String)
    case url(String)

    static func parse(_ input: String) -> TaskIdentifier {
        if input.contains("dooray.com") {
            return .url(input)
        }

        if input.wholeMatch(of: doorayIdPattern) != nil {
            return .taskId(input)
        }

        if input.contains("/") {
            let parts = input.split(separator: "/", maxSplits: 1)
            if parts.count == 2 {
                return .projectAndTask(
                    projectCode: String(parts[0]),
                    taskNumber: String(parts[1])
                )
            }
        }

        return .taskId(input)
    }
}

enum DoorayURLResult: Sendable {
    /// /project/{project-code}/task/{task-number}
    case projectCodeAndNumber(projectCode: String, taskNumber: String)
    /// /task/{project-id}/{post-id}
    case projectIdAndPostId(projectId: String, postId: String)
    /// /project/tasks/{post-id}
    case postId(String)
}

/// 두레이 URL에서 프로젝트/태스크 정보를 추출
func parseDoorayURL(_ urlString: String) -> DoorayURLResult? {
    guard let url = URL(string: urlString.removingPercentEncoding ?? urlString) ?? URL(string: urlString) else {
        return nil
    }

    let pathComponents = url.pathComponents.filter { $0 != "/" }

    // 패턴 1: /project/{project-code}/task/{task-number}
    if let projectIdx = pathComponents.firstIndex(of: "project"),
       projectIdx + 1 < pathComponents.count,
       let taskIdx = pathComponents.firstIndex(of: "task"),
       taskIdx + 1 < pathComponents.count {
        return .projectCodeAndNumber(
            projectCode: pathComponents[projectIdx + 1],
            taskNumber: pathComponents[taskIdx + 1]
        )
    }

    // 패턴 2: /task/{project-id}/{post-id}
    if let taskIdx = pathComponents.firstIndex(of: "task"),
       taskIdx + 2 < pathComponents.count {
        return .projectIdAndPostId(
            projectId: pathComponents[taskIdx + 1],
            postId: pathComponents[taskIdx + 2]
        )
    }

    // 패턴 3: /project/tasks/{post-id}
    if let tasksIdx = pathComponents.firstIndex(of: "tasks"),
       tasksIdx + 1 < pathComponents.count {
        return .postId(pathComponents[tasksIdx + 1])
    }

    // 패턴 4: /project/projects/{project-code}/{task-number}
    if let projectsIdx = pathComponents.firstIndex(of: "projects"),
       projectsIdx + 2 < pathComponents.count {
        return .projectCodeAndNumber(
            projectCode: pathComponents[projectsIdx + 1],
            taskNumber: pathComponents[projectsIdx + 2]
        )
    }

    return nil
}

func splitComma(_ value: String?) -> [String]? {
    value?.split(separator: ",").map(String.init)
}


/// --body(텍스트) 또는 --body-file(파일) 입력을 (본문, 이미지 상대경로 기준 디렉토리)로 변환
/// 텍스트 입력은 현재 작업 디렉토리, 파일 입력은 해당 파일의 디렉토리를 기준으로 한다.
func loadMarkdownBody(text: String?, file: String?) throws -> (content: String, baseDir: URL)? {
    if file == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (String(decoding: data, as: UTF8.self), URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
    if let file {
        let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        let content = try String(contentsOf: url, encoding: .utf8)
        return (content, url.deletingLastPathComponent())
    }
    if let text {
        return (text, URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
    return nil
}

/// 본문의 이미지 참조에서 경로 부분의 위치를 문서 순서대로 찾는다.
/// 마크다운 `![이름](경로)` 와, 크기를 지정할 때 쓰는 HTML `<img src="경로" width="…">` 둘 다 본다.
private func imagePathRanges(in content: String) -> [Range<String.Index>] {
    let markdown = /!\[[^\]]*\]\(([^)\n]+)\)/
    let html = /<img\b[^>]*?\bsrc\s*=\s*["']([^"'\n]+)["']/.ignoresCase()
    let ranges = content.matches(of: markdown).map { $0.1.startIndex..<$0.1.endIndex }
        + content.matches(of: html).map { $0.1.startIndex..<$0.1.endIndex }
    return ranges.sorted { $0.lowerBound < $1.lowerBound }
}

/// 이미지 경로가 업로드할 로컬 파일이면 그 URL 을, 아니면(URL, /files/ 참조, 없는 파일) nil 을 반환한다.
private func localImageURL(_ rawPath: Substring, baseDir: URL) -> URL? {
    let path = rawPath.trimmingCharacters(in: .whitespaces)
    if path.contains("://") || path.hasPrefix("data:") || path.hasPrefix("/files/") { return nil }
    let expanded = (path as NSString).expandingTildeInPath
    let fileURL = expanded.hasPrefix("/")
        ? URL(fileURLWithPath: expanded)
        : baseDir.appendingPathComponent(expanded).standardizedFileURL
    return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
}

/// 마크다운의 이미지 참조 중 실제로 업로드해야 하는 로컬 파일 경로만 골라 반환한다.
/// resolveInlineImages와 같은 판정 기준을 쓰므로, 업로드가 필요한지 미리 알아내는 데 사용한다.
func localImageURLs(in content: String, baseDir: URL) -> [URL] {
    imagePathRanges(in: content).compactMap { localImageURL(content[$0], baseDir: baseDir) }
}

/// 본문의 로컬 이미지 참조(![대체텍스트](경로), <img src="경로" …>)를 찾아 업로드 후 경로를 /files/{fileId}로 치환
/// 경로 외의 부분(대체텍스트, <img> 의 width 등 속성)은 그대로 둔다.
/// URL, /files/ 참조, 디스크에 존재하지 않는 경로는 그대로 둔다.
func resolveInlineImages(
    in content: String,
    baseDir: URL,
    upload: (URL) async throws -> String
) async throws -> String {
    var result = ""
    var lastIndex = content.startIndex
    var uploaded: [URL: String] = [:]  // 같은 파일을 여러 번 참조해도 한 번만 올린다
    for range in imagePathRanges(in: content) {
        guard let fileURL = localImageURL(content[range], baseDir: baseDir) else { continue }
        let fileId: String
        if let cached = uploaded[fileURL] {
            fileId = cached
        } else {
            fileId = try await upload(fileURL)
            uploaded[fileURL] = fileId
        }
        result += content[lastIndex..<range.lowerBound]
        result += "/files/\(fileId)"
        lastIndex = range.upperBound
    }
    result += content[lastIndex...]
    return result
}

/// 업무 본문·댓글에 붙여 넣는 위키 페이지 참조 링크. 두레이가 https 위키 URL 대신 이 형식을 페이지 참조로 렌더링한다.
/// 링크 텍스트의 [ ] 는 마크다운 링크를 깨뜨리므로 &#91; &#93; 로 바꾼다.
func wikiPageReference(id: String, subject: String, organizationId: String) -> String {
    let text = subject.replacingOccurrences(of: "[", with: "&#91;").replacingOccurrences(of: "]", with: "&#93;")
    return "[\(text)](dooray://\(organizationId)/pages/\(id) \"publish\")"
}

func csvEscape(_ value: String) -> String {
    let cleaned = value.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: "")
    if cleaned.contains(",") || cleaned.contains("\"") {
        return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return cleaned
}

extension Optional {
    func asyncMap<U>(_ transform: (Wrapped) async throws -> U) async rethrows -> U? {
        guard let self else { return nil }
        return try await transform(self)
    }
}

/// 옵션 형태가 아닌데 `-` 로 시작하는 위치 인자(댓글 `->@담당자 …` 등)를 `--` 뒤로 옮긴다.
///
/// ArgumentParser 는 `-` 로 시작하는 토큰을 짧은 옵션 묶음으로 읽는다. 그래서 `->[@홍길동](…) alpha 빌드에서 수정`
/// 는 글자 중 `h` 때문에 `-h`(도움말)로 해석돼 도움말만 출력하고 종료 코드 0 으로 끝난다 — 댓글은
/// 작성되지 않는데 성공처럼 보인다. 옵션처럼 생기지 않은 토큰(영문자 외 글자가 섞인 것)만 옮기고,
/// 값을 받는 옵션 바로 뒤의 토큰은 그 옵션의 값이므로 건드리지 않는다.
func escapeDashLeadingPositionals(_ arguments: [String]) -> [String] {
    // 값을 받지 않는 플래그. 이 뒤에 오는 토큰은 옵션 값이 아니라 위치 인자다.
    let flags: Set<String> = ["-h", "--help", "--body-only", "--json", "--mine", "--inline"]
    func looksLikeOption(_ token: String) -> Bool {
        token.wholeMatch(of: /--[A-Za-z][A-Za-z0-9-]*(=.*)?/) != nil
            || token.wholeMatch(of: /-[A-Za-z]+/) != nil
    }

    var kept: [String] = []
    var moved: [String] = []
    for (index, token) in arguments.enumerated() {
        if token == "--" {
            kept += arguments[index...]
            break
        }
        let previous = kept.last
        let previousTakesValue = previous.map {
            looksLikeOption($0) && !$0.contains("=") && !flags.contains($0)
        } ?? false
        if token.hasPrefix("-"), token != "-", !looksLikeOption(token), !previousTakesValue {
            moved.append(token)
        } else {
            kept.append(token)
        }
    }
    guard !moved.isEmpty else { return arguments }
    if let separator = kept.firstIndex(of: "--") {
        kept.insert(contentsOf: moved, at: separator + 1)
        return kept
    }
    return kept + ["--"] + moved
}

/// 위키 페이지 ID 또는 위키 페이지 URL 에서 페이지 ID 를 꺼낸다.
/// URL 은 경로의 마지막 19자리 숫자를 페이지 ID 로 본다 (예: https://…/wiki/{위키ID}/{페이지ID}).
func parseWikiPageId(_ input: String) throws -> String {
    if input.wholeMatch(of: doorayIdPattern) != nil {
        return input
    }
    if let url = URL(string: input),
       let pageId = url.pathComponents.last(where: { $0.wholeMatch(of: doorayIdPattern) != nil }) {
        return pageId
    }
    throw DoorayError.invalidIdentifier(input)
}
