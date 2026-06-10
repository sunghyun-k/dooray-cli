import Foundation

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

/// 마크다운에서 로컬 이미지 참조(![대체텍스트](경로))를 찾아 업로드 후 /files/{fileId}로 치환
/// URL, /files/ 참조, 디스크에 존재하지 않는 경로는 그대로 둔다.
func resolveInlineImages(
    in content: String,
    baseDir: URL,
    upload: (URL) async throws -> String
) async throws -> String {
    let imagePattern = /!\[([^\]]*)\]\(([^)\n]+)\)/

    var result = ""
    var lastIndex = content.startIndex
    for match in content.matches(of: imagePattern) {
        result += content[lastIndex..<match.range.lowerBound]
        lastIndex = match.range.upperBound

        let path = String(match.2).trimmingCharacters(in: .whitespaces)
        if path.contains("://") || path.hasPrefix("data:") || path.hasPrefix("/files/") {
            result += content[match.range]
            continue
        }

        let expanded = (path as NSString).expandingTildeInPath
        let fileURL = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : baseDir.appendingPathComponent(expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            result += content[match.range]
            continue
        }

        let fileId = try await upload(fileURL)
        result += "![\(match.1)](/files/\(fileId))"
    }
    result += content[lastIndex...]
    return result
}

func csvEscape(_ value: String) -> String {
    let cleaned = value.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: "")
    if cleaned.contains(",") || cleaned.contains("\"") {
        return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return cleaned
}
