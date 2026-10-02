import Foundation

struct ResolvedMember: Sendable {
    let id: String
    let name: String

    /// 두레이 멘션 마크다운. 댓글·본문에 쓰면 해당 멤버에게 알림이 간다.
    func mention(organizationId: String) -> String {
        "[@\(name)](dooray://\(organizationId)/members/\(id) \"member\")"
    }
}

/// 업무 담당자·참조자로 지정할 대상. 멤버 또는 프로젝트 멤버 그룹.
enum ResolvedUser: Sendable {
    case member(ResolvedMember)
    case group(id: String, code: String)

    /// 업무 생성·수정 요청의 users.to/cc 원소
    var requestValue: [String: Any] {
        switch self {
        case let .member(member):
            ["type": "member", "member": ["organizationMemberId": member.id]]
        case let .group(id, _):
            ["type": "group", "group": ["projectMemberGroupId": id]]
        }
    }

    /// `task get` 의 담당자·참조자 표기와 같은 형식
    var label: String {
        switch self {
        case let .member(member): "\(member.name) (\(member.id))"
        case let .group(_, code): "\(code) [그룹]"
        }
    }

    private var key: String {
        switch self {
        case let .member(member): "member:\(member.id)"
        case let .group(id, _): "group:\(id)"
        }
    }

    static func unique(_ users: [ResolvedUser]) -> [ResolvedUser] {
        var seen = Set<String>()
        return users.filter { seen.insert($0.key).inserted }
    }
}

/// `--to`·`--cc` 로 받은 지정자를 조직 멤버 또는 프로젝트 멤버 그룹으로 해석한다.
///
/// 멤버 지정자: `author`(업무 등록자), 멤버 ID(19자리), 이메일, userCode, 이름.
/// 이름은 먼저 업무에 이미 등장한 사람(등록자·담당자·참조자·참조 그룹 구성원) 중에서 찾고,
/// 없으면 조직 전체에서 찾는다. 조직에서 동명이인이면 후보를 알려 주고 멈춘다.
///
/// 그룹 지정자: `group:<code>` 또는 `task get` 표기 그대로인 `<code> [그룹]`. code 대신 그룹 ID 도 받는다.
/// 그룹은 프로젝트에 속하므로 `projectId` 의 그룹에서만 찾는다.
struct MemberResolver {
    let client: DoorayClient
    /// 이름 해석 우선순위와 `author` 해석에 쓰는 업무. 업무 생성처럼 업무가 없으면 nil.
    let post: Post?
    /// 그룹 지정자를 찾을 프로젝트. nil 이면 그룹 지정자를 받지 않는다.
    var projectId: String?

    static let authorKeywords: Set<String> = ["author", "작성자", "등록자"]

    /// 멤버·그룹 지정자를 함께 해석한다. 업무 담당자·참조자 지정용.
    func resolveUsers(_ specs: [String]) async throws -> [ResolvedUser] {
        var groups: [MemberGroup]?
        var result: [ResolvedUser] = []
        for spec in specs {
            if let groupSpec = Self.groupSpec(spec) {
                guard let projectId else {
                    throw DoorayError.invalidInput("'\(spec)': 그룹을 찾을 프로젝트를 알 수 없습니다.")
                }
                if groups == nil {
                    groups = try await client.getProjectMemberGroups(projectId: projectId)
                }
                result.append(try group(groupSpec, in: groups ?? [], spec: spec))
            } else {
                result.append(.member(try await resolve(spec)))
            }
        }
        return ResolvedUser.unique(result)
    }

    /// `group:<code>`·`<code> [그룹]` 이면 code(또는 ID)를, 아니면 nil 을 반환한다.
    static func groupSpec(_ rawSpec: String) -> String? {
        let spec = rawSpec.trimmingCharacters(in: .whitespaces)
        if spec.lowercased().hasPrefix("group:") {
            return spec.dropFirst("group:".count).trimmingCharacters(in: .whitespaces)
        }
        if spec.hasSuffix("[그룹]") {
            return spec.dropLast("[그룹]".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// 그룹을 ID, `프로젝트코드/그룹코드`, 그룹코드 순으로 찾는다.
    /// 다른 프로젝트의 그룹은 API 로 목록을 볼 수 없으므로 업무에 이미 지정된 그룹에서만 찾는다.
    private func group(_ groupSpec: String, in groups: [MemberGroup], spec: String) throws -> ResolvedUser {
        let lowered = groupSpec.lowercased()
        if let existing = postGroups.first(where: {
            $0.projectMemberGroupId == groupSpec || $0.code?.lowercased() == lowered
        }), let id = existing.projectMemberGroupId {
            return .group(id: id, code: existing.code ?? id)
        }
        let found = groups.first { $0.id == groupSpec }
            ?? groups.first { $0.fullCode?.lowercased() == lowered }
            ?? groups.first { $0.code?.lowercased() == lowered }
        guard let found else {
            let available = groups.compactMap(\.code).joined(separator: ", ")
            throw DoorayError.invalidInput("""
                그룹을 찾을 수 없습니다: \(spec)
                프로젝트 그룹: \(available.isEmpty ? "(없음)" : available)
                """)
        }
        return .group(id: found.id, code: found.fullCode ?? found.id)
    }

    /// 업무의 담당자·참조자로 지정된 그룹
    private var postGroups: [PostGroup] {
        guard let users = post?.users else { return [] }
        return ((users.to ?? []) + (users.cc ?? [])).compactMap(\.group)
    }

    func resolve(_ rawSpec: String) async throws -> ResolvedMember {
        let spec = rawSpec.trimmingCharacters(in: .whitespaces).trimmingPrefix("@").description

        if Self.authorKeywords.contains(spec.lowercased()) {
            guard let from = post?.users?.from?.member, let id = from.organizationMemberId else {
                throw DoorayError.invalidInput("'\(rawSpec)': 업무 등록자를 알 수 없습니다.")
            }
            return ResolvedMember(id: id, name: from.name ?? id)
        }

        // 이름은 업무에 이미 등장한 사람을 먼저 본다 (조직 전체 동명이인보다 이 업무의 사람이 의도일 가능성이 높다).
        let known = postMembers.filter { $0.name == spec }
        if Set(known.map(\.id)).count == 1, let member = known.first {
            return member
        }

        var found = try await candidates(for: spec)
        let knownIds = Set(known.map(\.id))
        if found.count > 1, !knownIds.isEmpty {
            let narrowed = found.filter { knownIds.contains($0.id) }
            if !narrowed.isEmpty { found = narrowed }
        }
        return try single(found, spec: rawSpec)
    }

    /// 조직 전체에서 지정자와 정확히 일치하는 멤버를 모두 찾는다 (멤버 ID·이메일·이름·userCode 순).
    func candidates(for rawSpec: String) async throws -> [OrganizationMember] {
        let spec = rawSpec.trimmingCharacters(in: .whitespaces).trimmingPrefix("@").description

        if spec.wholeMatch(of: doorayIdPattern) != nil {
            return [try await client.getMember(id: spec)]
        }
        if spec.contains("@") {
            return try await client.searchMembers(email: spec)
                .filter { $0.email?.lowercased() == spec.lowercased() }
        }
        let byName = try await client.searchMembers(name: spec).filter { $0.name == spec }
        if !byName.isEmpty {
            return byName
        }
        // userCode 검색은 접두사 일치라 정확히 같은 것만 남긴다.
        return try await client.searchMembers(userCode: spec)
            .filter { $0.userCode?.lowercased() == spec.lowercased() }
    }

    /// 업무의 등록자·담당자·참조자(그룹 구성원 포함)
    private var postMembers: [ResolvedMember] {
        guard let users = post?.users else { return [] }
        var members: [PostMember] = []
        if let from = users.from?.member { members.append(from) }
        for user in (users.to ?? []) + (users.cc ?? []) {
            if let member = user.member { members.append(member) }
            members += user.group?.members ?? []
        }
        return members.compactMap { member in
            guard let id = member.organizationMemberId else { return nil }
            return ResolvedMember(id: id, name: member.name ?? id)
        }
    }

    private func single(_ found: [OrganizationMember], spec: String) throws -> ResolvedMember {
        guard let first = found.first else {
            throw DoorayError.invalidInput("멤버를 찾을 수 없습니다: \(spec)")
        }
        guard found.count == 1 else {
            let candidates = found
                .map { "  \($0.name ?? "") <\($0.email ?? "")> \($0.id)" }
                .joined(separator: "\n")
            throw DoorayError.invalidInput("""
                같은 이름의 멤버가 여러 명입니다: \(spec)
                \(candidates)
                이메일이나 멤버 ID 로 지정하세요.
                """)
        }
        return ResolvedMember(id: first.id, name: first.name ?? first.id)
    }
}
