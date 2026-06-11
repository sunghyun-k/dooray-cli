import ArgumentParser
import Foundation

@main
struct DoorayCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dooray-cli",
        abstract: "두레이 CLI",
        subcommands: [
            ProjectCommand.self,
            TaskCommand.self,
            CommentCommand.self,
            WorkflowCommand.self,
            TagCommand.self,
            FileCommand.self,
        ]
    )
}

// MARK: - Project Commands

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "프로젝트 관리",
        subcommands: [List.self, Members.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "프로젝트 목록 조회")

        @Option(name: .shortAndLong, help: "상태 필터 (active/archived)")
        var state: String?

        @Flag(name: .long, help: "내가 속한 프로젝트만 조회")
        var mine: Bool = false

        @Option(name: .shortAndLong, help: "페이지 번호")
        var page: Int = 0

        func run() async throws {
            let client = try DoorayClient()
            let projects = try await client.listProjects(page: page, state: state, member: mine ? "me" : nil)

            print("id,code,state,scope,description")
            for p in projects {
                let desc = csvEscape(p.description ?? "")
                print("\(p.id),\(csvEscape(p.code)),\(p.state ?? ""),\(p.scope ?? ""),\(desc)")
            }
        }
    }

    struct Members: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "프로젝트 멤버 조회")

        @Argument(help: "프로젝트 코드 또는 ID")
        var project: String

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)
            let members = try await client.getProjectMembers(projectId: projectId)

            print("id,name,email,role")
            for m in members {
                print(
                    "\(m.organizationMemberId ?? ""),\(csvEscape(m.memberName ?? "")),\(m.emailAddress ?? ""),\(m.role ?? "")"
                )
            }
        }
    }
}

// MARK: - Task Commands

struct TaskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        abstract: "태스크 관리",
        subcommands: [Get.self, List.self, Create.self, Update.self, SetWorkflow.self, SetParent.self]
    )

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 상세 조회")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let post = try await client.getPostWithProject(projectId: projectId, postId: postId)

            // 단건 조회 API 는 subTasks 를 응답에 포함하지 않으므로 parentPostId 필터로 별도 조회한다.
            let subPosts = try await client.listPosts(
                projectId: projectId,
                size: 100,
                order: "postNumber",
                parentPostId: postId
            )

            printPost(post, subPosts: subPosts)
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "프로젝트 태스크 목록 조회")

        @Argument(help: "프로젝트 코드 또는 ID")
        var project: String

        @Option(name: .shortAndLong, help: "페이지 번호")
        var page: Int = 0

        @Option(name: .shortAndLong, help: "워크플로우 클래스 필터 (backlog,registered,working,closed)")
        var workflow: String?

        @Option(name: .shortAndLong, parsing: .unconditional, help: "정렬 (createdAt, -createdAt, postUpdatedAt, -postUpdatedAt)")
        var order: String?

        @Option(name: .long, help: "담당자 멤버 ID (쉼표 구분)")
        var toMemberIds: String?

        @Option(name: .long, help: "작성자 필터 (me 또는 멤버 ID, 쉼표 구분)")
        var createdBy: String?

        @Option(name: .long, help: "생성일 필터 (today, thisweek, prev-Nd, next-Nd, 또는 ISO8601~ISO8601 범위)")
        var createdAt: String?

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)
            let workflowClasses = splitComma(workflow)
            let toMembers = splitComma(toMemberIds)

            var fromMembers: [String]? = nil
            if let createdBy {
                if createdBy.lowercased() == "me" {
                    let me = try await client.getMemberMe()
                    fromMembers = [me.id]
                } else {
                    fromMembers = splitComma(createdBy)
                }
            }

            let posts = try await client.listPosts(
                projectId: projectId,
                page: page,
                workflowClasses: workflowClasses,
                toMemberIds: toMembers,
                fromMemberIds: fromMembers,
                order: order,
                createdAt: createdAt
            )

            print("number,subject,status,priority,assignee,updated,ended_at")
            for p in posts {
                let assignee = p.users?.to?.compactMap { $0.member?.name }.joined(separator: ";") ?? ""
                print(
                    "\(p.number ?? 0),\(csvEscape(p.subject ?? "")),\(p.workflowClass ?? ""),\(p.priority ?? ""),\(csvEscape(assignee)),\(p.updatedAt ?? ""),\(p.endedAt ?? "")"
                )
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 생성")

        @Argument(help: "프로젝트 코드 또는 ID")
        var project: String

        @Argument(help: "태스크 제목")
        var subject: String

        @Option(name: .shortAndLong, help: "태스크 본문 (마크다운, 로컬 이미지 경로는 현재 디렉토리 기준 자동 업로드)")
        var body: String?

        @Option(name: .long, help: "본문으로 사용할 마크다운 파일 (이미지 상대경로는 이 파일 기준)")
        var bodyFile: String?

        @Option(name: .shortAndLong, help: "우선순위 (highest/high/normal/low/lowest)")
        var priority: String?

        @Option(name: .shortAndLong, help: "마감일 (ISO 8601)")
        var dueDate: String?

        @Option(name: .long, help: "담당자 멤버 ID (쉼표 구분)")
        var to: String?

        @Option(name: .long, help: "상위 태스크 (태스크 ID, 프로젝트코드/번호, 또는 URL) — 하위 태스크로 생성")
        var parent: String?

        func validate() throws {
            if body != nil && bodyFile != nil {
                throw ValidationError("--body와 --body-file은 동시에 사용할 수 없습니다.")
            }
        }

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)

            var parentPostId: String?
            if let parent {
                let (parentProjectId, resolvedParentId) = try await client.resolveTask(parent)
                guard parentProjectId == projectId else {
                    throw ValidationError("상위 태스크가 다른 프로젝트에 있습니다. 같은 프로젝트의 태스크만 상위로 지정할 수 있습니다.")
                }
                parentPostId = resolvedParentId
            }

            let usersTo = splitComma(to)
            let markdownBody = try loadMarkdownBody(text: body, file: bodyFile)

            let taskId = try await client.createPost(
                projectId: projectId,
                subject: subject,
                bodyContent: markdownBody?.content,
                usersTo: usersTo,
                priority: priority,
                dueDate: dueDate,
                parentPostId: parentPostId
            )

            // 인라인 이미지 업로드는 postId가 필요하므로 생성 후 본문을 치환해 갱신한다.
            if let (content, baseDir) = markdownBody {
                let resolved = try await resolveInlineImages(in: content, baseDir: baseDir) { fileURL in
                    print("이미지 업로드 중: \(fileURL.lastPathComponent)...")
                    return try await client.uploadFile(projectId: projectId, postId: taskId, fileURL: fileURL, inline: true)
                }
                if resolved != content {
                    try await client.updatePost(projectId: projectId, postId: taskId, bodyContent: resolved)
                }
            }

            print("태스크 생성 완료: \(taskId)")
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 수정")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Option(name: .shortAndLong, help: "제목")
        var subject: String?

        @Option(name: .shortAndLong, help: "본문 (마크다운, 로컬 이미지 경로는 현재 디렉토리 기준 자동 업로드)")
        var body: String?

        @Option(name: .long, help: "본문으로 사용할 마크다운 파일 (이미지 상대경로는 이 파일 기준)")
        var bodyFile: String?

        @Option(name: .shortAndLong, help: "우선순위")
        var priority: String?

        func validate() throws {
            if body != nil && bodyFile != nil {
                throw ValidationError("--body와 --body-file은 동시에 사용할 수 없습니다.")
            }
        }

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            var bodyContent: String?
            if let (content, baseDir) = try loadMarkdownBody(text: body, file: bodyFile) {
                bodyContent = try await resolveInlineImages(in: content, baseDir: baseDir) { fileURL in
                    print("이미지 업로드 중: \(fileURL.lastPathComponent)...")
                    return try await client.uploadFile(projectId: projectId, postId: postId, fileURL: fileURL, inline: true)
                }
            }

            try await client.updatePost(
                projectId: projectId,
                postId: postId,
                subject: subject,
                bodyContent: bodyContent,
                priority: priority
            )

            print("태스크 수정 완료: \(postId)")
        }
    }

    struct SetParent: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-parent",
            abstract: "기존 태스크를 다른 태스크의 하위 태스크로 연결"
        )

        @Argument(help: "하위로 만들 태스크 (태스크 ID, 프로젝트코드/번호, 또는 URL)")
        var identifier: String

        @Argument(help: "상위 태스크 (태스크 ID, 프로젝트코드/번호, 또는 URL)")
        var parent: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let (parentProjectId, parentPostId) = try await client.resolveTask(parent)

            guard parentProjectId == projectId else {
                throw ValidationError("상위 태스크가 다른 프로젝트에 있습니다. 같은 프로젝트의 태스크만 상위로 지정할 수 있습니다.")
            }
            guard parentPostId != postId else {
                throw ValidationError("자기 자신을 상위 태스크로 지정할 수 없습니다.")
            }

            try await client.setPostParent(projectId: projectId, postId: postId, parentPostId: parentPostId)

            print("상위 태스크 설정 완료: \(postId) → 상위 \(parentPostId)")
        }
    }

    struct SetWorkflow: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-workflow",
            abstract: "태스크 워크플로우(상태) 변경"
        )

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Argument(help: "워크플로우 ID")
        var workflowId: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            try await client.setPostWorkflow(projectId: projectId, postId: postId, workflowId: workflowId)

            print("워크플로우 변경 완료: \(postId)")
        }
    }
}

// MARK: - Comment Commands

struct CommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "댓글 관리",
        subcommands: [List.self, Create.self, Update.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "댓글 목록 조회")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Option(name: .shortAndLong, help: "페이지 번호")
        var page: Int = 0

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let logs = try await client.listLogs(projectId: projectId, postId: postId, page: page)

            // creator 이름 일괄 조회
            let commentLogs = logs.filter { $0.subtype == "user" || $0.type == "comment" }
            var memberNames: [String: String] = [:]
            let creatorIds = Set(commentLogs.compactMap { $0.creator?.member?.organizationMemberId })
            for id in creatorIds {
                if let member = try? await client.getMember(id: id) {
                    memberNames[id] = member.name
                }
            }

            print("id,creator,content,created_at")
            for log in commentLogs {
                let creatorName = log.creator?.member?.organizationMemberId.flatMap { memberNames[$0] } ?? ""
                let content = csvEscape(log.body?.content ?? "")
                print(
                    "\(log.id),\(csvEscape(creatorName)),\(content),\(log.createdAt ?? "")"
                )
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "댓글 작성")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Argument(help: "댓글 내용 (마크다운, 로컬 이미지 경로는 현재 디렉토리 기준 자동 업로드)")
        var content: String?

        @Option(name: .long, help: "댓글 내용으로 사용할 마크다운 파일 (이미지 상대경로는 이 파일 기준)")
        var bodyFile: String?

        func validate() throws {
            if (content == nil) == (bodyFile == nil) {
                throw ValidationError("댓글 내용 또는 --body-file 중 하나를 지정해야 합니다.")
            }
        }

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            guard let (body, baseDir) = try loadMarkdownBody(text: content, file: bodyFile) else {
                throw ValidationError("댓글 내용 또는 --body-file 중 하나를 지정해야 합니다.")
            }
            let resolved = try await resolveInlineImages(in: body, baseDir: baseDir) { fileURL in
                print("이미지 업로드 중: \(fileURL.lastPathComponent)...")
                return try await client.uploadFile(projectId: projectId, postId: postId, fileURL: fileURL, inline: true)
            }

            let logId = try await client.createLog(
                projectId: projectId,
                postId: postId,
                content: resolved
            )

            print("댓글 작성 완료: \(logId)")
        }
    }
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "댓글 수정")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Argument(help: "댓글 ID")
        var logId: String

        @Argument(help: "수정할 내용")
        var content: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            try await client.updateLog(
                projectId: projectId,
                postId: postId,
                logId: logId,
                content: content
            )

            print("댓글 수정 완료: \(logId)")
        }
    }
}

// MARK: - Workflow Commands

struct WorkflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "워크플로우 관리",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "워크플로우 목록 조회")

        @Argument(help: "프로젝트 코드 또는 ID")
        var project: String

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)
            let workflows = try await client.getWorkflows(projectId: projectId)

            print("id,name,class")
            for w in workflows {
                let name = w.names?.ko ?? w.name ?? ""
                print("\(w.id),\(csvEscape(name)),\(w.class ?? "")")
            }
        }
    }
}

// MARK: - Tag Commands

struct TagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "태그 관리",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태그 목록 조회")

        @Argument(help: "프로젝트 코드 또는 ID")
        var project: String

        @Option(name: .shortAndLong, help: "페이지 번호")
        var page: Int = 0

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)
            let tags = try await client.listTags(projectId: projectId, page: page)

            print("id,name,color")
            for t in tags {
                print("\(t.id),\(csvEscape(t.name ?? "")),\(t.color ?? "")")
            }
        }
    }
}

// MARK: - File Commands

struct FileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "첨부파일 관리",
        subcommands: [List.self, Download.self, Upload.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 첨부파일 목록 조회")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let post = try await client.getPostWithProject(projectId: projectId, postId: postId)

            guard let files = post.files, !files.isEmpty else {
                print("첨부파일이 없습니다.")
                return
            }

            print("id,name,size,url")
            for file in files {
                let name = csvEscape(file.name ?? "")
                let size = file.size.map { "\($0)" } ?? ""
                let downloadURL = client.fileDownloadURL(fileId: file.id)
                print("\(file.id),\(name),\(size),\(downloadURL)")
            }
        }
    }

    struct Upload: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크에 첨부파일 업로드")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Argument(help: "업로드할 파일 경로 (여러 개 가능)")
        var files: [String]

        @Flag(name: .long, help: "본문/댓글 인라인 이미지용으로 업로드 (첨부 목록에 표시되지 않음, ![이름](/files/{fileId})로 참조)")
        var inline: Bool = false

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            for path in files {
                let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw DoorayError.apiError(statusCode: 0, message: "파일을 찾을 수 없습니다: \(path)")
                }
                print("업로드 중: \(fileURL.lastPathComponent)...")
                let fileId = try await client.uploadFile(projectId: projectId, postId: postId, fileURL: fileURL, inline: inline)
                print("완료: \(fileId)")
            }
        }
    }

    struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "첨부파일 다운로드")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Option(name: .shortAndLong, help: "저장 디렉토리 (기본: 현재 디렉토리)")
        var output: String?

        @Argument(help: "다운로드할 파일 ID (생략 시 전체 다운로드)")
        var fileId: String?

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let post = try await client.getPostWithProject(projectId: projectId, postId: postId)

            guard let files = post.files, !files.isEmpty else {
                print("첨부파일이 없습니다.")
                return
            }

            let targetFiles: [PostFile]
            if let fileId {
                guard let file = files.first(where: { $0.id == fileId }) else {
                    throw DoorayError.apiError(statusCode: 0, message: "파일 ID '\(fileId)'를 찾을 수 없습니다.")
                }
                targetFiles = [file]
            } else {
                targetFiles = files
            }

            let outputDir: URL
            if let output {
                outputDir = URL(fileURLWithPath: output)
            } else {
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dooray-files")
                    .appendingPathComponent(postId)
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                outputDir = tmpDir
            }

            for file in targetFiles {
                let fileName = file.name ?? file.id
                let destination = outputDir.appendingPathComponent(fileName)
                print("다운로드 중: \(fileName)...")
                try await client.downloadFile(projectId: projectId, postId: postId, fileId: file.id, to: destination)
                print("완료: \(destination.path)")
            }
        }
    }
}

// MARK: - Output Helpers

func printPost(_ post: Post, subPosts: [Post] = []) {
    print("ID: \(post.id)")
    if let taskNumber = post.taskNumber {
        print("번호: \(taskNumber)")
    } else if let num = post.number, let code = post.project?.code {
        print("번호: \(code)/\(num)")
    }
    print("제목: \(post.subject ?? "")")
    print("상태: \(post.workflowClass ?? "") (\(post.workflow?.name ?? ""))")
    print("우선순위: \(post.priority ?? "none")")

    if let from = post.users?.from?.member?.name {
        print("작성자: \(from)")
    }

    if let to = post.users?.to, !to.isEmpty {
        let names = to.compactMap { $0.member?.name }.joined(separator: ", ")
        print("담당자: \(names)")
    }

    if let cc = post.users?.cc, !cc.isEmpty {
        let names = cc.compactMap { $0.member?.name }.joined(separator: ", ")
        print("참조자: \(names)")
    }

    if let dueDate = post.dueDate {
        print("마감일: \(dueDate)")
    }

    if let milestone = post.milestone {
        print("마일스톤: \(milestone.name ?? milestone.id)")
    }

    if let tags = post.tags, !tags.isEmpty {
        let tagNames = tags.compactMap { $0.name }.joined(separator: ", ")
        print("태그: \(tagNames)")
    }

    if let parent = post.parent {
        let parentInfo = parent.subject ?? "#\(parent.number ?? 0)"
        print("상위 태스크: \(parentInfo)")
    }

    if let fileIds = post.fileIdList, !fileIds.isEmpty {
        print("첨부파일: \(fileIds.count)개")
    }

    print("생성일: \(post.createdAt ?? "")")
    print("수정일: \(post.updatedAt ?? "")")
    if let endedAt = post.endedAt {
        print("완료일: \(endedAt)")
    }

    if let body = post.body?.content, !body.isEmpty {
        print("\n--- 본문 ---")
        print(body)
    }

    if !subPosts.isEmpty {
        print("\n--- 하위 태스크 (\(subPosts.count)개) ---")
        for sub in subPosts {
            let number: String
            if let taskNumber = sub.taskNumber {
                number = taskNumber
            } else if let num = sub.number, let code = sub.project?.code {
                number = "\(code)/\(num)"
            } else {
                number = sub.id
            }
            print("  \(number) [\(sub.workflowClass ?? "")] \(sub.subject ?? "")")
        }
    }
}
