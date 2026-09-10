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
        // validate()를 걸지 않는다 — 4xx/5xx 응답 본문에 담긴 두레이 resultMessage를
        // 읽어 사용자에게 전달해야 하기 때문이다. 상태 코드 판정은 decodeResponse가 한다.
        let dataTask = session.request(
            "\(baseURL)\(path)",
            parameters: parameters,
            encoder: URLEncodedFormParameterEncoder.default,
            headers: headers
        )

        let dataResponse = await dataTask.serializingData().response
        guard let data = dataResponse.value else {
            throw DoorayError.networkError(dataResponse.error?.localizedDescription ?? "Unknown error")
        }

        return try decodeResponse(data: data, statusCode: dataResponse.response?.statusCode ?? 0, path: path)
    }

    /// 응답 본문을 디코딩하고, 실패 응답이면 두레이가 내려준 resultMessage를 담아 오류를 던진다.
    private func decodeResponse<T: Decodable & Sendable>(
        data: Data,
        statusCode: Int,
        path: String
    ) throws -> DoorayResponse<T> {
        let decoded: DoorayResponse<T>
        do {
            decoded = try JSONDecoder().decode(DoorayResponse<T>.self, from: data)
        } catch {
            // 실패 응답은 result 스키마가 달라 디코딩이 깨지므로 헤더만 먼저 읽어 본다.
            if let header = try? JSONDecoder().decode(HeaderOnlyResponse.self, from: data).header,
               !header.isSuccessful {
                throw DoorayError.apiError(statusCode: statusCode, message: header.readableMessage)
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw DoorayError.apiError(
                statusCode: statusCode,
                message: "디코딩 실패 (\(path)): \(error)\n\n응답: \(raw.prefix(500))"
            )
        }

        guard decoded.header.isSuccessful else {
            throw DoorayError.apiError(statusCode: statusCode, message: decoded.header.readableMessage)
        }
        guard (200..<300).contains(statusCode) else {
            throw DoorayError.apiError(statusCode: statusCode, message: decoded.header.readableMessage)
        }
        return decoded
    }

    private struct HeaderOnlyResponse: Decodable, Sendable {
        let header: ResponseHeader
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

        // get과 같은 이유로 validate()를 걸지 않는다 — 400 응답의 resultMessage
        // (예: USER_INVALID_TAG_MANDATORY_PREFIX)를 그대로 사용자에게 보여주기 위함.
        let dataResponse = await session.request(urlRequest).serializingData().response
        guard let data = dataResponse.value else {
            throw DoorayError.networkError(dataResponse.error?.localizedDescription ?? "Unknown error")
        }

        return try decodeResponse(data: data, statusCode: dataResponse.response?.statusCode ?? 0, path: path)
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
        createdAt: String? = nil,
        parentPostId: String? = nil
    ) async throws -> [Post] {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let workflowClasses { params["postWorkflowClasses"] = workflowClasses.joined(separator: ",") }
        if let toMemberIds { params["toMemberIds"] = toMemberIds.joined(separator: ",") }
        if let fromMemberIds { params["fromMemberIds"] = fromMemberIds.joined(separator: ",") }
        if let order { params["order"] = order }
        if let createdAt { params["createdAt"] = createdAt }
        if let parentPostId { params["parentPostId"] = parentPostId }

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
        tagIds: [String]? = nil,
        parentPostId: String? = nil
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
        if let parentPostId { dict["parentPostId"] = parentPostId }

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
        bodyMimeType: String = "text/x-markdown",
        priority: String? = nil,
        tagIds: [String]? = nil
    ) async throws {
        var dict: [String: Any] = [:]
        if let subject { dict["subject"] = subject }
        if let bodyContent { dict["body"] = ["content": bodyContent, "mimeType": bodyMimeType] }
        if let priority { dict["priority"] = priority }
        if let tagIds { dict["tagIds"] = tagIds }

        let _: DoorayResponse<Post> = try await mutate(method: .put,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)",
            jsonData: jsonData(dict)
        )
    }

    func setPostParent(projectId: String, postId: String, parentPostId: String) async throws {
        let _: DoorayResponse<CreateResult> = try await mutate(method: .post,
            path: "/project/v1/projects/\(projectId)/posts/\(postId)/set-parent-post",
            jsonData: jsonData(["parentPostId": parentPostId])
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

    /// 프로젝트의 모든 태그를 페이지 끝까지 모아서 반환한다.
    func listAllTags(projectId: String) async throws -> [Tag] {
        var all: [Tag] = []
        for page in 0..<20 {
            let tags = try await listTags(projectId: projectId, page: page, size: 100)
            if tags.isEmpty { break }
            all += tags
            if tags.count < 100 { break }
        }
        return all
    }

    /// `--tag` 로 받은 태그 이름 또는 ID 목록을 태그 ID 목록으로 변환한다.
    /// 이름 비교는 대소문자와 공백을 무시하며, 그룹 접두사를 생략한 짧은 이름(예: iOS)도 허용한다.
    /// 해석에 실패하면 프로젝트의 선택 가능한 태그를 함께 알려 준다.
    func resolveTagIds(projectId: String, specs: [String]) async throws -> [String] {
        guard !specs.isEmpty else { return [] }
        let tags = try await listAllTags(projectId: projectId)

        func normalize(_ value: String) -> String {
            value.lowercased().filter { !$0.isWhitespace }
        }

        var resolved: [String] = []
        for spec in specs {
            let key = normalize(spec)
            if let byId = tags.first(where: { $0.id == spec }) {
                resolved.append(byId.id)
                continue
            }
            if let byName = tags.first(where: { normalize($0.name ?? "") == key }) {
                resolved.append(byName.id)
                continue
            }
            // 그룹 접두사를 생략한 짧은 이름 (예: "iOS" → "Platform: iOS")
            let shortMatches = tags.filter { tag in
                guard let name = tag.name, let group = tag.tagGroup?.name else { return false }
                let stripped = name.dropFirst(group.count).drop(while: { $0 == ":" || $0.isWhitespace })
                return normalize(String(stripped)) == key
            }
            if shortMatches.count == 1 {
                resolved.append(shortMatches[0].id)
                continue
            }
            if shortMatches.count > 1 {
                let candidates = shortMatches.compactMap(\.name).joined(separator: ", ")
                throw DoorayError.invalidInput(
                    "태그 이름이 모호합니다: \(spec)\n후보: \(candidates)\n전체 이름으로 지정하세요."
                )
            }
            let available = tags.compactMap(\.name).sorted().joined(separator: ", ")
            throw DoorayError.invalidInput(
                "태그를 찾을 수 없습니다: \(spec)\n사용 가능한 태그: \(available)"
            )
        }
        return Array(NSOrderedSet(array: resolved)) as? [String] ?? resolved
    }

    /// 필수 태그 그룹이 비어 있으면 어떤 그룹에 무엇을 지정해야 하는지 알려 주는 오류를 던진다.
    /// 두레이 서버는 USER_INVALID_TAG_MANDATORY_PREFIX 만 반환해 어떤 그룹인지 알려 주지 않는다.
    func validateMandatoryTags(projectId: String, tagIds: [String]) async throws {
        let tags = try await listAllTags(projectId: projectId)
        let selectedGroupIds = Set(tags.filter { tagIds.contains($0.id) }.compactMap { $0.tagGroup?.id })

        var missing: [(group: String, options: [String])] = []
        var seenGroups = Set<String>()
        for tag in tags {
            guard let group = tag.tagGroup, group.mandatory == true else { continue }
            guard !selectedGroupIds.contains(group.id), !seenGroups.contains(group.id) else { continue }
            seenGroups.insert(group.id)
            let options = tags
                .filter { $0.tagGroup?.id == group.id }
                .compactMap(\.name)
                .sorted()
            missing.append((group.name ?? group.id, options))
        }

        guard !missing.isEmpty else { return }
        let detail = missing
            .map { "  [\($0.group)] \($0.options.joined(separator: ", "))" }
            .joined(separator: "\n")
        throw DoorayError.invalidInput("""
            이 프로젝트는 다음 태그 그룹을 필수로 요구합니다. --tag 로 각 그룹에서 하나 이상 지정하세요.
            \(detail)
            """)
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

    /// inline: true 시 본문/댓글 인라인 이미지용으로 업로드되며 일반 첨부 목록에 표시되지 않는다.
    /// 업로드 후 마크다운에서 ![이름](/files/{반환된 ID})로 참조한다.
    func uploadFile(projectId: String, postId: String, fileURL: URL, inline: Bool = false) async throws -> String {
        let url = "\(baseURL)/project/v1/projects/\(projectId)/posts/\(postId)/files"

        // type 필드는 file 필드보다 먼저 전송되어야 한다.
        let formData: @Sendable (MultipartFormData) -> Void = { form in
            if inline {
                form.append(Data("inline_image".utf8), withName: "type")
            }
            form.append(fileURL, withName: "file")
        }

        // 1차 요청은 307과 location 헤더를 반환한다. 자동 리다이렉트 시
        // Authorization 헤더와 본문이 유실되므로 직접 location으로 재요청한다.
        let firstResponse = await session.upload(
            multipartFormData: formData,
            to: url,
            headers: headers
        )
        .redirect(using: Redirector(behavior: .doNotFollow))
        .serializingData()
        .response

        var uploadURL = url
        if let status = firstResponse.response?.statusCode {
            if (300..<400).contains(status) {
                guard let location = firstResponse.response?.headers["Location"] else {
                    throw DoorayError.apiError(statusCode: status, message: "파일 업로드 리다이렉트 location 헤더가 없습니다.")
                }
                uploadURL = location
            } else if (200..<300).contains(status), let data = firstResponse.value,
                      let response = try? JSONDecoder().decode(DoorayResponse<CreateResult>.self, from: data),
                      let id = response.result?.id {
                return id
            } else {
                let raw = firstResponse.value.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                throw DoorayError.apiError(statusCode: status, message: "파일 업로드 실패: \(raw.prefix(500))")
            }
        } else {
            throw DoorayError.networkError(firstResponse.error?.localizedDescription ?? "Unknown error")
        }

        let response = try await session.upload(
            multipartFormData: formData,
            to: uploadURL,
            headers: headers
        )
        .validate()
        .serializingDecodable(DoorayResponse<CreateResult>.self)
        .value

        guard let id = response.result?.id else {
            throw DoorayError.apiError(statusCode: 0, message: "파일 업로드 실패: \(response.header.resultMessage ?? "")")
        }
        return id
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
