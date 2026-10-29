import Foundation

/// 模拟器通讯录默认是空的，先灌几个人，才演得出「换公司 / 换职位」的对比
@MainActor
enum DemoSeed {
    struct Person {
        let name: String
        let company: String
        let position: String
        let phone: String
    }

    static let people: [Person] = [
        Person(name: "王建国", company: "恒安设计院", position: "合规总监", phone: "13800000001"),
        Person(name: "李静", company: "C 公司", position: "运营总监", phone: "13800000002"),
        Person(name: "陈默", company: "C 公司", position: "支付产品负责人", phone: "13800000003"),
        Person(name: "赵敏", company: "恒瑞资本", position: "投资经理", phone: "13900000009"),
        Person(name: "周海涛", company: "远洋物流", position: "采购主管", phone: "13800000004"),
        Person(name: "吴颖", company: "星禾传媒", position: "市场经理", phone: "13800000005"),
        Person(name: "徐立", company: "北岸科技", position: "CTO", phone: "13800000006"),
        Person(name: "郭倩", company: "华信律所", position: "合伙人", phone: "13800000007"),
    ]

    static func fillDeviceContacts() async throws -> Int {
        guard await ContactsService.shared.requestAccess() else {
            throw APIError(message: "通讯录权限被拒绝，去系统设置里打开")
        }
        var count = 0
        for person in people {
            try ContactsService.shared.upsert(
                name: person.name,
                phone: person.phone,
                email: nil,
                company: person.company,
                position: person.position
            )
            count += 1
        }
        return count
    }
}
