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

    private func mutate<T: Decodable & Sendable>(
        method: HTTPMethod,
        path: String,
        jsonData: Data
    ) async throws -> DoorayResponse<T> {
        var urlRequest = try URLRequest(url: "\(baseURL)\(path)", method: method)
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

    /// API가 result를 배열 또는 { contents: [...] }로 반환하는 경우를 통합 처리
    private struct ListResult<T: Decodable & Sendable>: Decodable, Sendable {
        let contents: [T]?
    }

    private func getList<T: Decodable & Sendable>(
        path: String,
        parameters: [String: String] = [:]
    ) async throws -> [T] {
        do {
            let response: DoorayResponse<[T]> = try await get(path: path, parameters: parameters)
            return response.result ?? []
        } catch {
            let response: DoorayResponse<ListResult<T>> = try await get(path: path, parameters: parameters)
            return response.result?.contents ?? []
        }
    }

    // MARK: - Projects

    func listProjects(page: Int = 0, size: Int = 20, state: String? = nil, type: String? = nil, member: String? = nil) async throws -> [Project] {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let state { params["state"] = state }
        if let type { params["type"] = type }
        if let member { params["member"] = member }

        let response: DoorayResponse<[Project]> = try await get(path: "/project/v1/projects", parameters: params)
        return response.result ?? []
    }

    func findProjectByCode(_ code: String) async throws -> Project? {
        // @ 접두사는 개인(private) 프로젝트, 그 외는 public 먼저 검색
        let types: [String?] = code.hasPrefix("@") ? ["private"] : [nil, "private"]
        for type in types {
            for page in 0..<20 {
                let projects = try await listProjects(page: page, size: 100, type: type)
                if projects.isEmpty { break }
                if let found = projects.first(where: {
                    $0.code.lowercased() == code.lowercased()
                }) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: - Current User

    func getMemberMe() async throws -> OrganizationMember {
        let response: DoorayResponse<OrganizationMember> = try await get(path: "/common/v1/members/me")
        guard let member = response.result else {
            throw DoorayError.apiError(statusCode: 0, message: "현재 사용자 정보를 가져올 수 없습니다.")
        }
        return member
    }

    func getMember(id: String) async throws -> OrganizationMember {
        let response: DoorayResponse<OrganizationMember> = try await get(path: "/common/v1/members/\(id)")
        guard let member = response.result else {
            throw DoorayError.apiError(statusCode: 0, message: "멤버 정보를 가져올 수 없습니다: \(id)")
        }
        return member
    }

    // MARK: - Members

    func getProjectMembers(projectId: String, page: Int = 0, size: Int = 20) async throws -> [Member] {
        try await getList(
            path: "/project/v1/projects/\(projectId)/members",
            parameters: ["page": "\(page)", "size": "\(size)"]
        )
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
        fromMemberIds: [String]? = nil,
        order: String? = nil,
        createdAtFrom: String? = nil,
        createdAtTo: String? = nil
    ) async throws -> [Post] {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let workflowClasses { params["postWorkflowClasses"] = workflowClasses.joined(separator: ",") }
        if let toMemberIds { params["toMemberIds"] = toMemberIds.joined(separator: ",") }
        if let fromMemberIds { params["fromMemberIds"] = fromMemberIds.joined(separator: ",") }
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

        let response: DoorayResponse<CreateResult> = try await mutate(method: .post,
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

        let _: DoorayResponse<Post> = try await mutate(method: .put,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)",
            jsonData: jsonData(dict)
        )
    }

    func setPostWorkflow(projectId: String, postId: String, workflowId: String) async throws {
        let _: DoorayResponse<CreateResult> = try await mutate(method: .post,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/set-workflow",
            jsonData: jsonData(["workflowId": workflowId])
        )
    }

    // MARK: - Workflows

    func getWorkflows(projectId: String) async throws -> [Workflow] {
        try await getList(path: "/project/v1/projects/\(projectId)/workflows")
    }

    // MARK: - Tags

    func listTags(projectId: String, page: Int = 0, size: Int = 20) async throws -> [Tag] {
        try await getList(
            path: "/project/v1/projects/\(projectId)/tags",
            parameters: ["page": "\(page)", "size": "\(size)"]
        )
    }

    // MARK: - Logs (Comments)

    func listLogs(projectId: String, postId: String, page: Int = 0, size: Int = 20) async throws -> [Log] {
        try await getList(
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/logs",
            parameters: ["page": "\(page)", "size": "\(size)"]
        )
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
        let response: DoorayResponse<CreateResult> = try await mutate(method: .post,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/logs",
            jsonData: jsonData(dict)
        )
        guard let id = response.result?.id else {
            throw DoorayError.apiError(statusCode: 0, message: "댓글 생성 실패")
        }
        return id
    }

    func updateLog(
        projectId: String,
        postId: String,
        logId: String,
        content: String,
        mimeType: String = "text/x-markdown"
    ) async throws {
        let dict: [String: Any] = [
            "body": ["content": content, "mimeType": mimeType],
        ]
        let _: DoorayResponse<CreateResult> = try await mutate(method: .put,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/logs/\(logId)",
            jsonData: jsonData(dict)
        )
    }

    // MARK: - Files

    /// 테넌트 base URL 생성
    /// DOORAY_TENANT 환경변수: 테넌트 코드 (예: your-tenant) 또는 전체 URL (예: https://your-tenant.dooray.com)
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

    func downloadFile(projectId: String, postId: String, fileId: String, to destination: URL) async throws {
        let url = "\(baseURL)/project/v1/projects/\(projectId)/posts/\(postId)/files/\(fileId)?media=raw"

        // 307 리다이렉트 시 Authorization 헤더를 유지하도록 설정
        let authHeaders = headers
        let redirector = Redirector(behavior: .modify { _, request, _ in
            var request = request
            for header in authHeaders.dictionary {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
            return request
        })

        let dest: DownloadRequest.Destination = { _, _ in
            (destination, [.removePreviousFile, .createIntermediateDirectories])
        }
        let response = await session.download(url, headers: authHeaders, to: dest)
            .redirect(using: redirector)
            .validate()
            .serializingDownload(using: URLResponseSerializer())
            .response

        if let error = response.error {
            throw DoorayError.networkError("파일 다운로드 실패: \(error.localizedDescription)")
        }
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
            switch parsed {
            case .projectIdAndPostId(let projectId, let postId):
                return (projectId, postId)
            case .projectCodeAndNumber(let projectCode, let taskNumber):
                guard let project = try await findProjectByCode(projectCode) else {
                    throw DoorayError.projectNotFound(projectCode)
                }
                guard let post = try await getPostByNumber(projectId: project.id, postNumber: taskNumber) else {
                    throw DoorayError.taskNotFound(urlString)
                }
                return (project.id, post.id)
            case .postId(let postId):
                let post = try await getPost(postId: postId)
                guard let projectId = post.project?.id else {
                    throw DoorayError.taskNotFound(urlString)
                }
                return (projectId, post.id)
            }
        }
    }

    func resolveProjectId(_ codeOrId: String) async throws -> String {
        if codeOrId.wholeMatch(of: doorayIdPattern) != nil {
            return codeOrId
        }
        guard let project = try await findProjectByCode(codeOrId) else {
            throw DoorayError.projectNotFound(codeOrId)
        }
        return project.id
    }
}
