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

        @Option(name: .shortAndLong, help: "페이지 번호")
        var page: Int = 0

        func run() async throws {
            let client = try DoorayClient()
            let projects = try await client.listProjects(page: page, state: state)

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
        subcommands: [Get.self, List.self, Create.self, Update.self, SetWorkflow.self]
    )

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 상세 조회")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)
            let post = try await client.getPostWithProject(projectId: projectId, postId: postId)

            printPost(post)
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

        @Option(name: .shortAndLong, help: "정렬 (createdAt, -createdAt, postUpdatedAt, -postUpdatedAt)")
        var order: String?

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)
            let workflowClasses = workflow?.split(separator: ",").map(String.init)
            let posts = try await client.listPosts(
                projectId: projectId,
                page: page,
                workflowClasses: workflowClasses,
                order: order
            )

            print("number,subject,status,priority,assignee,updated")
            for p in posts {
                let assignee = p.users?.to?.compactMap { $0.member?.name }.joined(separator: ";") ?? ""
                print(
                    "\(p.number ?? 0),\(csvEscape(p.subject ?? "")),\(p.workflowClass ?? ""),\(p.priority ?? ""),\(csvEscape(assignee)),\(p.updatedAt ?? "")"
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

        @Option(name: .shortAndLong, help: "태스크 본문 (마크다운)")
        var body: String?

        @Option(name: .shortAndLong, help: "우선순위 (highest/high/normal/low/lowest)")
        var priority: String?

        @Option(name: .shortAndLong, help: "마감일 (ISO 8601)")
        var dueDate: String?

        @Option(name: .long, help: "담당자 멤버 ID (쉼표 구분)")
        var to: String?

        func run() async throws {
            let client = try DoorayClient()
            let projectId = try await client.resolveProjectId(project)

            let usersTo = to?.split(separator: ",").map(String.init)

            let taskId = try await client.createPost(
                projectId: projectId,
                subject: subject,
                bodyContent: body,
                usersTo: usersTo,
                priority: priority,
                dueDate: dueDate
            )

            print("태스크 생성 완료: \(taskId)")
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "태스크 수정")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Option(name: .shortAndLong, help: "제목")
        var subject: String?

        @Option(name: .shortAndLong, help: "본문 (마크다운)")
        var body: String?

        @Option(name: .shortAndLong, help: "우선순위")
        var priority: String?

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            try await client.updatePost(
                projectId: projectId,
                postId: postId,
                subject: subject,
                bodyContent: body,
                priority: priority
            )

            print("태스크 수정 완료: \(postId)")
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
        subcommands: [List.self, Create.self]
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

            print("id,creator,content,created_at")
            for log in logs where log.subtype == "user" || log.type == "comment" {
                let content = csvEscape(log.body?.content ?? "")
                print(
                    "\(log.id),\(csvEscape(log.creator?.name ?? "")),\(content),\(log.createdAt ?? "")"
                )
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "댓글 작성")

        @Argument(help: "태스크 ID, 프로젝트코드/번호, 또는 URL")
        var identifier: String

        @Argument(help: "댓글 내용")
        var content: String

        func run() async throws {
            let client = try DoorayClient()
            let (projectId, postId) = try await client.resolveTask(identifier)

            let logId = try await client.createLog(
                projectId: projectId,
                postId: postId,
                content: content
            )

            print("댓글 작성 완료: \(logId)")
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
        subcommands: [List.self]
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
}

// MARK: - Output Helpers

func printPost(_ post: Post) {
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

    if let body = post.body?.content, !body.isEmpty {
        print("\n--- 본문 ---")
        print(body)
    }

    if let subTasks = post.subTasks, !subTasks.isEmpty {
        print("\n--- 하위 태스크 (\(subTasks.count)개) ---")
        for sub in subTasks {
            print("  [\(sub.workflowClass ?? "")] \(sub.subject ?? sub.id)")
        }
    }
}
