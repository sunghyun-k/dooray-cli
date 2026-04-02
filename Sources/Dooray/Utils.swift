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


func csvEscape(_ value: String) -> String {
    let cleaned = value.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: "")
    if cleaned.contains(",") || cleaned.contains("\"") {
        return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return cleaned
}
