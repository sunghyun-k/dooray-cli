import Foundation

struct ResolvedMember: Sendable {
    let id: String
    let name: String

    /// 두레이 멘션 마크다운. 댓글·본문에 쓰면 해당 멤버에게 알림이 간다.
    func mention(organizationId: String) -> String {
        "[@\(name)](dooray://\(organizationId)/members/\(id) \"member\")"
    }
}

/// `--to`·`--cc` 로 받은 멤버 지정자를 조직 멤버로 해석한다.
///
/// 지정자: `author`(업무 등록자), 멤버 ID(19자리), 이메일, userCode, 이름.
/// 이름은 먼저 업무에 이미 등장한 사람(등록자·담당자·참조자·참조 그룹 구성원) 중에서 찾고,
/// 없으면 조직 전체에서 찾는다. 조직에서 동명이인이면 후보를 알려 주고 멈춘다.
struct MemberResolver {
    let client: DoorayClient
    /// 이름 해석 우선순위와 `author` 해석에 쓰는 업무. 업무 생성처럼 업무가 없으면 nil.
    let post: Post?

    static let authorKeywords: Set<String> = ["author", "작성자", "등록자"]

    func resolve(_ specs: [String]) async throws -> [ResolvedMember] {
        var result: [ResolvedMember] = []
        for spec in specs {
            let member = try await resolve(spec)
            if !result.contains(where: { $0.id == member.id }) {
                result.append(member)
            }
        }
        return result
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
