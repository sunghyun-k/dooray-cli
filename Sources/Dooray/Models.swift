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

struct MemberGroup: Decodable, Sendable {
    let id: String
    let name: String?
    let members: [Member]?
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
    let creator: LogCreator?
    let createdAt: String?
    let modifiedAt: String?
}

struct LogCreator: Decodable, Sendable {
    let id: String?
    let name: String?
    let emailAddress: String?
}

// MARK: - List Results

struct MemberGroupListResult: Decodable, Sendable {
    let contents: [MemberGroup]?
}

struct CreateResult: Decodable, Sendable {
    let id: String?
}

// MARK: - File

struct FileInfo: Decodable, Sendable {
    let id: String
    let name: String?
    let size: Int?
    let mimeType: String?
    let createdAt: String?
}
