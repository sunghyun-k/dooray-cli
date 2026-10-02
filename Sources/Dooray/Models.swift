import Foundation

// MARK: - API Response Wrapper

struct DoorayResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let header: ResponseHeader
    let result: T?
    let totalCount: Int?
}

struct ResponseHeader: Decodable, Sendable {
    let resultCode: Int
    let resultMessage: String?
    let isSuccessful: Bool

    private enum CodingKeys: String, CodingKey {
        case resultCode, resultMessage, isSuccessful
    }

    // 실패 응답은 header에 resultCode/isSuccessful을 생략하는 경우가 있어 기본값을 둔다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultCode = try container.decodeIfPresent(Int.self, forKey: .resultCode) ?? -1
        resultMessage = try container.decodeIfPresent(String.self, forKey: .resultMessage)
        isSuccessful = try container.decodeIfPresent(Bool.self, forKey: .isSuccessful) ?? false
    }

    /// 두레이는 메시지가 없을 때 "null" 문자열이나 빈 문자열을 내려주기도 한다.
    var readableMessage: String {
        guard let message = resultMessage,
              !message.isEmpty,
              message != "null"
        else {
            return "두레이가 오류 메시지를 반환하지 않았습니다. (resultCode: \(resultCode))"
        }
        return message
    }
}

// MARK: - Project

struct Project: Decodable, Sendable {
    let id: String
    let code: String
    let description: String?
    let state: String?
    let scope: String?
}

// MARK: - Member

struct Member: Decodable, Sendable {
    let organizationMemberId: String?
    let memberName: String?
    let emailAddress: String?
    let role: String?
}

/// 프로젝트 멤버 그룹. 업무 담당자·참조자로 지정할 수 있다. 이름은 `code` 에 들어 있다.
struct MemberGroup: Decodable, Sendable {
    let id: String
    let code: String?
    let project: PostProject?

    /// 업무 조회 응답(`PostGroup.code`)과 같은 `프로젝트코드/그룹코드` 형식
    var fullCode: String? {
        guard let code else { return nil }
        guard let projectCode = project?.code else { return code }
        return "\(projectCode)/\(code)"
    }
}

// MARK: - Post (Task)

struct Post: Decodable, Sendable {
    let id: String
    let subject: String?
    let taskNumber: String?
    let number: Int?
    let project: PostProject?
    let body: PostBody?
    let closed: Bool?
    let workflowClass: String?
    let workflow: Workflow?
    let priority: String?
    let users: PostUsers?
    let createdAt: String?
    let updatedAt: String?
    let endedAt: String?
    let dueDate: String?
    let dueDateFlag: Bool?
    let milestone: Milestone?
    let tags: [Tag]?
    let parent: PostRef?
    let subTasks: [SubTask]?
    let fileIdList: [String]?
    let files: [PostFile]?
}

struct PostFile: Decodable, Sendable {
    let id: String
    let name: String?
    let size: Int?
}

struct PostProject: Decodable, Sendable {
    let id: String
    let code: String?
}

struct PostBody: Decodable, Sendable {
    let content: String?
    let mimeType: String?
}

struct PostUsers: Decodable, Sendable {
    let from: PostUser?
    let to: [PostUser]?
    let cc: [PostUser]?
    let me: [PostUser]?
}

struct PostUser: Decodable, Sendable {
    let type: String?
    let member: PostMember?
    let group: PostGroup?
    let emailUser: PostEmailUser?

    /// 사람이 읽는 표시용 문자열. 멤버는 멘션·필터에 쓸 수 있도록 ID 를 함께 붙인다.
    var displayName: String {
        if let member {
            return "\(member.name ?? "") (\(member.organizationMemberId ?? ""))"
        }
        if let group {
            return "\(group.code ?? group.projectMemberGroupId ?? "") [그룹]"
        }
        if let emailUser {
            return "\(emailUser.name ?? "") <\(emailUser.emailAddress ?? "")>"
        }
        return type ?? ""
    }

    /// 업무 수정(PUT) 요청에 되돌려 보낼 수 있는 형태. 응답 전용 필드(이름, workflow 등)는 뺀다.
    var requestValue: [String: Any]? {
        if let id = member?.organizationMemberId {
            return ["type": "member", "member": ["organizationMemberId": id]]
        }
        if let id = group?.projectMemberGroupId {
            return ["type": "group", "group": ["projectMemberGroupId": id]]
        }
        if let email = emailUser?.emailAddress {
            return ["type": "emailUser", "emailUser": ["emailAddress": email, "name": emailUser?.name ?? ""]]
        }
        return nil
    }
}

struct PostGroup: Decodable, Sendable {
    let projectMemberGroupId: String?
    let code: String?
    let members: [PostMember]?
}

struct PostEmailUser: Decodable, Sendable {
    let emailAddress: String?
    let name: String?
}

struct PostMember: Decodable, Sendable {
    let organizationMemberId: String?
    let name: String?
    let emailAddress: String?
}

struct Milestone: Decodable, Sendable {
    let id: String
    let name: String?
}

struct PostRef: Decodable, Sendable {
    let id: String
    let number: Int?
    let subject: String?
}

struct SubTask: Decodable, Sendable {
    let id: String
    let subject: String?
    let workflowClass: String?
}

// MARK: - Workflow

struct Workflow: Decodable, Sendable {
    let id: String
    let name: String?
    let names: WorkflowNames?
    let `class`: String?

    enum CodingKeys: String, CodingKey {
        case id, name, names
        case `class` = "class"
    }
}

struct WorkflowNames: Sendable {
    let ko: String?
    let en: String?
    let ja: String?
    let zh: String?
}

private struct WorkflowLocaleName: Decodable {
    let locale: String
    let name: String
}

extension WorkflowNames: Decodable {
    init(from decoder: Decoder) throws {
        // API returns either {"ko":"...", "en":"..."} or [{"locale":"ko_KR","name":"..."}]
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            ko = try container.decodeIfPresent(String.self, forKey: .ko)
            en = try container.decodeIfPresent(String.self, forKey: .en)
            ja = try container.decodeIfPresent(String.self, forKey: .ja)
            zh = try container.decodeIfPresent(String.self, forKey: .zh)
        } else if let items = try? decoder.singleValueContainer().decode([WorkflowLocaleName].self) {
            ko = items.first(where: { $0.locale.hasPrefix("ko") })?.name
            en = items.first(where: { $0.locale.hasPrefix("en") })?.name
            ja = items.first(where: { $0.locale.hasPrefix("ja") })?.name
            zh = items.first(where: { $0.locale.hasPrefix("zh") })?.name
        } else {
            ko = nil; en = nil; ja = nil; zh = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ko, en, ja, zh
    }
}

// MARK: - Tag

struct Tag: Decodable, Sendable {
    let id: String
    let name: String?
    let color: String?
    let tagGroupId: String?
    /// 태그 목록 API는 소속 그룹과 그룹의 필수 여부를 함께 반환한다.
    let tagGroup: TagGroupRef?
}

/// 태그에 포함되어 오는 소속 그룹 정보
struct TagGroupRef: Decodable, Sendable {
    let id: String
    let name: String?
    /// 이 그룹의 태그를 반드시 하나 이상 지정해야 하는지
    let mandatory: Bool?
    /// 이 그룹에서 하나만 선택할 수 있는지
    let selectOne: Bool?
}

struct TagGroup: Decodable, Sendable {
    let id: String
    let name: String?
    let isMandatory: Bool?
    let isSelectOne: Bool?
    let tags: [Tag]?
}

// MARK: - Log (Comment)

struct Log: Decodable, Sendable {
    let id: String
    let type: String?
    let subtype: String?
    let body: PostBody?
    let creator: PostUser?
    let createdAt: String?
    let modifiedAt: String?
}

// MARK: - List Results

struct CreateResult: Decodable, Sendable {
    let id: String?
}

// MARK: - Organization Member (me)

struct OrganizationMember: Decodable, Sendable {
    let id: String
    let name: String?
    let emailAddress: String?
    let userCode: String?
    let externalEmailAddress: String?
    /// 멘션 링크(dooray://{조직ID}/members/{멤버ID})에 쓰는 조직 ID. members/me 응답에만 있다.
    let defaultOrganization: OrganizationRef?

    var email: String? { externalEmailAddress ?? emailAddress }
}

struct OrganizationRef: Decodable, Sendable {
    let id: String
}

// MARK: - File

struct FileInfo: Decodable, Sendable {
    let id: String
    let name: String?
    let size: Int?
    let mimeType: String?
    let createdAt: String?
}
