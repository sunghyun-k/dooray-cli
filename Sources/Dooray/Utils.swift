import Foundation

/// 두레이 URL 또는 식별자를 파싱하여 (projectId, postId) 또는 (projectCode, taskNumber)를 반환
enum TaskIdentifier: Sendable {
    case taskId(String)
    case projectAndTask(projectCode: String, taskNumber: String)
    case url(String)

    static func parse(_ input: String) -> TaskIdentifier {
        if input.contains("dooray.com") {
            return .url(input)
        }

        let idPattern = /^\d{19}$/
        if input.wholeMatch(of: idPattern) != nil {
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

/// 두레이 URL에서 프로젝트 코드와 태스크 번호를 추출
func parseDoorayURL(_ urlString: String) -> (projectCode: String, taskNumber: String)? {
    guard let url = URL(string: urlString.removingPercentEncoding ?? urlString) ?? URL(string: urlString) else {
        return nil
    }

    let pathComponents = url.pathComponents.filter { $0 != "/" }

    // /project/{project-code}/task/{task-number} 패턴
    guard let projectIdx = pathComponents.firstIndex(of: "project"),
          projectIdx + 1 < pathComponents.count else {
        return nil
    }

    let projectCode = pathComponents[projectIdx + 1]

    guard let taskIdx = pathComponents.firstIndex(of: "task"),
          taskIdx + 1 < pathComponents.count else {
        return nil
    }

    let taskPart = pathComponents[taskIdx + 1]
    return (projectCode, taskPart)
}

func csvEscape(_ value: String) -> String {
    let cleaned = value.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: "")
    if cleaned.contains(",") || cleaned.contains("\"") {
        return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return cleaned
}
