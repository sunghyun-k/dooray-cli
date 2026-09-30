import Foundation

enum DoorayError: Error, CustomStringConvertible {
    case missingToken
    case apiError(statusCode: Int, message: String)
    case networkError(String)
    case invalidIdentifier(String)
    case projectNotFound(String)
    case taskNotFound(String)
    /// 요청을 보내기 전에 CLI가 걸러낸 입력 오류 (태그 이름 오타, 필수 태그 누락 등)
    case invalidInput(String)

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
            """
            프로젝트를 찾을 수 없습니다: \(code)
            두레이 API 는 프로젝트를 코드로 조회하지 못해 프로젝트 목록에서 찾는데, 목록에는 공개 프로젝트와
            내가 참여한 비공개 프로젝트만 나옵니다. 참여하지 않은 비공개 프로젝트나 다른 사람의 개인 프로젝트는
            업무 ID 나 업무 URL(https://…/project/tasks/{업무ID})로 지정하세요.
            """
        case .taskNotFound(let id):
            "태스크를 찾을 수 없습니다: \(id)"
        case .invalidInput(let message):
            message
        }
    }
}
