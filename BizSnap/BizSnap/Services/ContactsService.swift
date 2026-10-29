import Contacts
import Foundation

/// 系统通讯录：读快照给 agent 判断「已在通讯录」，确认后写真实联系人
@MainActor
final class ContactsService {
    static let shared = ContactsService()

    private let store = CNContactStore()

    private let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    var status: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// 最多 200 条，只带 name / company / position / phones
    func snapshot(limit: Int = 200) -> [ContactSnapshot] {
        guard status == .authorized else { return [] }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault

        var result: [ContactSnapshot] = []
        try? store.enumerateContacts(with: request) { contact, stop in
            if result.count >= limit {
                stop.pointee = true
                return
            }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            guard !name.isEmpty else { return }
            result.append(
                ContactSnapshot(
                    name: name,
                    company: contact.organizationName.isEmpty ? nil : contact.organizationName,
                    position: contact.jobTitle.isEmpty ? nil : contact.jobTitle,
                    phones: contact.phoneNumbers.isEmpty
                        ? nil
                        : contact.phoneNumbers.map { $0.value.stringValue }
                )
            )
        }
        return result
    }

    /// 按姓名 upsert：系统通讯录只能承载姓名 / 电话 / 邮箱 / 公司 / 职位
    @discardableResult
    func upsert(
        name: String,
        phone: String?,
        email: String?,
        company: String?,
        position: String?
    ) throws -> String {
        let existing = try find(name: name)
        let save = CNSaveRequest()

        if let existing, let mutable = existing.mutableCopy() as? CNMutableContact {
            if let phone, !phone.isEmpty { mutable.phoneNumbers = [phoneEntry(phone, existing: mutable)] }
            if let email, !email.isEmpty { mutable.emailAddresses = [emailEntry(email, existing: mutable)] }
            if let company, !company.isEmpty { mutable.organizationName = company }
            if let position, !position.isEmpty { mutable.jobTitle = position }
            save.update(mutable)
            try store.execute(save)
            return "已更新通讯录里的\(name)"
        }

        let contact = CNMutableContact()
        contact.givenName = name
        if let phone, !phone.isEmpty { contact.phoneNumbers = [phoneEntry(phone, existing: nil)] }
        if let email, !email.isEmpty { contact.emailAddresses = [emailEntry(email, existing: nil)] }
        if let company, !company.isEmpty { contact.organizationName = company }
        if let position, !position.isEmpty { contact.jobTitle = position }
        save.add(contact, toContainerWithIdentifier: nil)
        try store.execute(save)
        return "已写入通讯录：\(name)"
    }

    private func find(name: String) throws -> CNContact? {
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        return matches.first {
            (CNContactFormatter.string(from: $0, style: .fullName) ?? "") == name
        }
    }

    private func phoneEntry(_ number: String, existing: CNMutableContact?) -> CNLabeledValue<CNPhoneNumber> {
        if let old = existing?.phoneNumbers.first(where: { $0.value.stringValue == number }) {
            return old
        }
        return CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: number))
    }

    private func emailEntry(_ address: String, existing: CNMutableContact?) -> CNLabeledValue<NSString> {
        if let old = existing?.emailAddresses.first(where: { $0.value as String == address }) {
            return old
        }
        return CNLabeledValue(label: CNLabelWork, value: address as NSString)
    }
}
