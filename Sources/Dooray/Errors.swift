import Foundation

enum DoorayError: Error, CustomStringConvertible {
    case missingToken
    case apiError(statusCode: Int, message: String)
    case networkError(String)
    case invalidIdentifier(String)
    case projectNotFound(String)
    case taskNotFound(String)

    var description: String {
        switch self {
        case .missingToken:
            "DOORAY_API_TOKEN 환경변수가 설정되지 않았습니다."
        case .apiError(let statusCode, let message):
            "API 오류 (\(statusCode)): \(message)"
        case .networkError(let message):
            "네트워크 오류: \(message)"
        case .invalidIdentifier(let id):
            "잘못된 식별자: \(id)"
        case .projectNotFound(let code):
            "프로젝트를 찾을 수 없습니다: \(code)"
        case .taskNotFound(let id):
            "태스크를 찾을 수 없습니다: \(id)"
        }
    }
}
