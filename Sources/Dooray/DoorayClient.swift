@preconcurrency import Alamofire
import Foundation

final class DoorayClient: Sendable {
    let baseURL: String
    private let token: String
    private let session: Session

    init() throws {
        guard let token = ProcessInfo.processInfo.environment["DOORAY_API_TOKEN"], !token.isEmpty else {
            throw DoorayError.missingToken
        }
        self.token = token
        self.baseURL = ProcessInfo.processInfo.environment["DOORAY_API_BASE_URL"]
            ?? "https://api.dooray.com"
        self.session = Session(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            return config
        }())
    }

    private var headers: HTTPHeaders {
        ["Authorization": "dooray-api \(token)"]
    }

    // MARK: - Generic Request

    private func get<T: Decodable & Sendable>(
        path: String,
        parameters: [String: String] = [:]
    ) async throws -> DoorayResponse<T> {
        let dataTask = session.request(
            "\(baseURL)\(path)",
            parameters: parameters,
            encoder: URLEncodedFormParameterEncoder.default,
            headers: headers
        ).validate()

        let dataResponse = await dataTask.serializingData().response
        guard let data = dataResponse.value else {
            throw DoorayError.networkError(dataResponse.error?.localizedDescription ?? "Unknown error")
        }

        do {
            return try JSONDecoder().decode(DoorayResponse<T>.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw DoorayError.apiError(
                statusCode: dataResponse.response?.statusCode ?? 0,
                message: "디코딩 실패 (\(path)): \(error)\n\n응답: \(raw.prefix(500))"
            )
        }
    }

    private func post<T: Decodable & Sendable>(
        path: String,
        jsonData: Data
    ) async throws -> DoorayResponse<T> {
        var urlRequest = try URLRequest(url: "\(baseURL)\(path)", method: .post)
        urlRequest.headers = headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData

        return try await session.request(urlRequest)
            .validate()
            .serializingDecodable(DoorayResponse<T>.self)
            .value
    }

    private func put<T: Decodable & Sendable>(
        path: String,
        jsonData: Data
    ) async throws -> DoorayResponse<T> {
        var urlRequest = try URLRequest(url: "\(baseURL)\(path)", method: .put)
        urlRequest.headers = headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData

        return try await session.request(urlRequest)
            .validate()
            .serializingDecodable(DoorayResponse<T>.self)
            .value
    }

    // MARK: - JSON Helpers

    private func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Projects

    func listProjects(page: Int = 0, size: Int = 20, state: String? = nil) async throws -> [Project] {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let state { params["state"] = state }

        let response: DoorayResponse<[Project]> = try await get(path: "/project/v1/projects", parameters: params)
        return response.result ?? []
    }

    func findProjectByCode(_ code: String) async throws -> Project? {
        for page in 0..<20 {
            let projects = try await listProjects(page: page, size: 100)
            if projects.isEmpty { break }
            if let found = projects.first(where: {
                $0.code.lowercased() == code.lowercased()
            }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Members

    func getProjectMembers(projectId: String, page: Int = 0, size: Int = 20) async throws -> [Member] {
        let response: DoorayResponse<MemberListResult> = try await get(
            path: "/project/v1/projects/\(projectId)/members",
            parameters: ["page": "\(page)", "size": "\(size)"]
        )
        return response.result?.contents ?? []
    }

    func getProjectMemberGroups(projectId: String) async throws -> [MemberGroup] {
        let response: DoorayResponse<MemberGroupListResult> = try await get(
            path: "/project/v1/projects/\(projectId)/member-groups"
        )
        return response.result?.contents ?? []
    }

    // MARK: - Posts (Tasks)

    func getPost(postId: String) async throws -> Post {
        let response: DoorayResponse<Post> = try await get(
            path: "/project/v1/posts/\(postId)"
        )
        guard let post = response.result else {
            throw DoorayError.taskNotFound(postId)
        }
        return post
    }

    func getPostWithProject(projectId: String, postId: String) async throws -> Post {
        let response: DoorayResponse<Post> = try await get(
            path: "/project/v1/projects/\(projectId)/posts/\(postId)"
        )
        guard let post = response.result else {
            throw DoorayError.taskNotFound(postId)
        }
        return post
    }

    func listPosts(
        projectId: String,
        page: Int = 0,
        size: Int = 20,
        workflowClasses: [String]? = nil,
        toMemberIds: [String]? = nil,
        order: String? = nil,
        createdAtFrom: String? = nil,
        createdAtTo: String? = nil
    ) async throws -> [Post] {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let workflowClasses { params["postWorkflowClasses"] = workflowClasses.joined(separator: ",") }
        if let toMemberIds { params["toMemberIds"] = toMemberIds.joined(separator: ",") }
        if let order { params["order"] = order }
        if let createdAtFrom { params["createdAtFrom"] = createdAtFrom }
        if let createdAtTo { params["createdAtTo"] = createdAtTo }

        let response: DoorayResponse<[Post]> = try await get(
            path: "/project/v1/projects/\(projectId)/posts", parameters: params
        )
        return response.result ?? []
    }

    func getPostByNumber(projectId: String, postNumber: String) async throws -> Post? {
        let response: DoorayResponse<[Post]> = try await get(
            path: "/project/v1/projects/\(projectId)/posts",
            parameters: ["postNumber": postNumber, "size": "1"]
        )
        return response.result?.first
    }

    func createPost(
        projectId: String,
        subject: String,
        bodyContent: String? = nil,
        bodyMimeType: String = "text/x-markdown",
        usersTo: [String]? = nil,
        priority: String? = nil,
        dueDate: String? = nil,
        milestoneId: String? = nil,
        tagIds: [String]? = nil
    ) async throws -> String {
        var dict: [String: Any] = ["subject": subject]

        if let bodyContent {
            dict["body"] = ["content": bodyContent, "mimeType": bodyMimeType]
        }

        if let usersTo {
            dict["users"] = [
                "to": usersTo.map { id in
                    ["type": "member", "member": ["organizationMemberId": id]]
                },
            ]
        }

        if let priority { dict["priority"] = priority }
        if let dueDate { dict["dueDateFlag"] = true; dict["dueDate"] = dueDate }
        if let milestoneId { dict["milestoneId"] = milestoneId }
        if let tagIds { dict["tagIds"] = tagIds }

        let response: DoorayResponse<CreateResult> = try await post(
            path: "/project/v1/projects/\(projectId)/posts",
            jsonData: jsonData(dict)
        )
        guard let id = response.result?.id else {
            throw DoorayError.apiError(statusCode: 0, message: "태스크 생성 실패")
        }
        return id
    }

    func updatePost(
        projectId: String,
        postId: String,
        subject: String? = nil,
        bodyContent: String? = nil,
        priority: String? = nil
    ) async throws {
        var dict: [String: Any] = [:]
        if let subject { dict["subject"] = subject }
        if let bodyContent { dict["body"] = ["content": bodyContent, "mimeType": "text/x-markdown"] }
        if let priority { dict["priority"] = priority }

        let _: DoorayResponse<Post> = try await put(
            path: "/project/v1/projects/\(projectId)/posts/\(postId)",
            jsonData: jsonData(dict)
        )
    }

    func setPostWorkflow(projectId: String, postId: String, workflowId: String) async throws {
        let _: DoorayResponse<CreateResult> = try await post(
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/set-workflow",
            jsonData: jsonData(["workflowId": workflowId])
        )
    }

    // MARK: - Workflows

    func getWorkflows(projectId: String) async throws -> [Workflow] {
        let response: DoorayResponse<WorkflowListResult> = try await get(
            path: "/project/v1/projects/\(projectId)/workflows"
        )
        return response.result?.contents ?? []
    }

    // MARK: - Tags

    func listTags(projectId: String, page: Int = 0, size: Int = 20) async throws -> [Tag] {
        let response: DoorayResponse<TagListResult> = try await get(
            path: "/project/v1/projects/\(projectId)/tags",
            parameters: ["page": "\(page)", "size": "\(size)"]
        )
        return response.result?.contents ?? []
    }

    // MARK: - Logs (Comments)

    func listLogs(projectId: String, postId: String, page: Int = 0, size: Int = 20) async throws -> [Log] {
        let path = "/project/v1/projects/\(projectId)/posts/\(postId)/logs"
        let params = ["page": "\(page)", "size": "\(size)"]

        // API가 result를 배열 또는 딕셔너리로 반환할 수 있음
        do {
            let response: DoorayResponse<[Log]> = try await get(path: path, parameters: params)
            return response.result ?? []
        } catch {
            let response: DoorayResponse<LogListResult> = try await get(path: path, parameters: params)
            return response.result?.contents ?? []
        }
    }

    func createLog(
        projectId: String,
        postId: String,
        content: String,
        mimeType: String = "text/x-markdown"
    ) async throws -> String {
        let dict: [String: Any] = [
            "body": ["content": content, "mimeType": mimeType],
        ]
        let response: DoorayResponse<CreateResult> = try await post(
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/logs",
            jsonData: jsonData(dict)
        )
        guard let id = response.result?.id else {
            throw DoorayError.apiError(statusCode: 0, message: "댓글 생성 실패")
        }
        return id
    }

    // MARK: - Files

    /// 테넌트 base URL 생성
    /// DOORAY_TENANT 환경변수: 테넌트 코드 (예: nhnent) 또는 전체 URL (예: https://nhnent.dooray.com)
    static var tenantBaseURL: String? {
        guard let tenant = ProcessInfo.processInfo.environment["DOORAY_TENANT"], !tenant.isEmpty else {
            return nil
        }
        if tenant.hasPrefix("http://") || tenant.hasPrefix("https://") {
            return tenant
        }
        return "https://\(tenant).dooray.com"
    }

    func fileDownloadURL(fileId: String) -> String {
        guard let base = Self.tenantBaseURL else {
            return "/files/\(fileId)"
        }
        return "\(base)/files/\(fileId)"
    }

    // MARK: - Task Identifier Resolution

    func resolveTask(_ identifier: String) async throws -> (projectId: String, postId: String) {
        let parsed = TaskIdentifier.parse(identifier)

        switch parsed {
        case .taskId(let id):
            let post = try await getPost(postId: id)
            guard let projectId = post.project?.id else {
                throw DoorayError.taskNotFound(id)
            }
            return (projectId, post.id)

        case .projectAndTask(let projectCode, let taskNumber):
            guard let project = try await findProjectByCode(projectCode) else {
                throw DoorayError.projectNotFound(projectCode)
            }
            guard let post = try await getPostByNumber(projectId: project.id, postNumber: taskNumber) else {
                throw DoorayError.taskNotFound("\(projectCode)/\(taskNumber)")
            }
            return (project.id, post.id)

        case .url(let urlString):
            guard let parsed = parseDoorayURL(urlString) else {
                throw DoorayError.invalidIdentifier(urlString)
            }
            guard let project = try await findProjectByCode(parsed.projectCode) else {
                throw DoorayError.projectNotFound(parsed.projectCode)
            }
            guard let post = try await getPostByNumber(projectId: project.id, postNumber: parsed.taskNumber) else {
                throw DoorayError.taskNotFound(urlString)
            }
            return (project.id, post.id)
        }
    }

    func resolveProjectId(_ codeOrId: String) async throws -> String {
        let idPattern = /^\d{19}$/
        if codeOrId.wholeMatch(of: idPattern) != nil {
            return codeOrId
        }
        guard let project = try await findProjectByCode(codeOrId) else {
            throw DoorayError.projectNotFound(codeOrId)
        }
        return project.id
    }
}
