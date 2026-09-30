import SwiftUI
import WebKit

// MARK: - Sign up

/// The My RCH Portal Request Form, as the RCH website embeds it.
struct SignUpFormView: View {
    static let formURL = URL(string: "https://forms.office.com/Pages/ResponsePage.aspx?id=UweTC-D4dUC7lmXVZKjcrreVhb_r1etPrI_CUP5CdcNUOThFTDFDWkRWQUhOWTRWSEVCSzgyNUpXTy4u&embed=true")!

    @Environment(\.dismiss) private var dismiss
    @State private var page = WebPage()

    var body: some View {
        NavigationStack {
            WebView(page)
                .webViewLinkPreviews(.disabled)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if page.isLoading && page.estimatedProgress < 0.5 {
                        ProgressView("Loading form…")
                    }
                }
                .navigationTitle("Sign Up")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { page.load(URLRequest(url: Self.formURL)) }
    }
}

// MARK: - Help

/// One question from the portal's FAQ.
private struct FAQItem: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

private struct FAQSection: Identifiable {
    let title: String
    let items: [FAQItem]
    var id: String { title }
}

/// The portal's FAQ (myrchportal.rch.org.au, Login › FAQ), with a way to
/// call the Help Desk and to sign up.
struct PortalHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsSignUp = false

    /// The Help Desk; "Option 1 for EMR" is the portal line.
    private static let helpDeskURL = URL(string: "tel:+61393456277")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link(destination: Self.helpDeskURL) {
                        SettingsRow("Call the Help Desk", symbol: "phone.fill", color: .green, showsChevron: true)
                    }
                    .foregroundStyle(.primary)
                    Button {
                        showsSignUp = true
                    } label: {
                        SettingsRow("Request an Account", symbol: "person.badge.plus", color: Theme.brand)
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Help Desk: (03) 9345 6277, then Option 1 for EMR.")
                }

                ForEach(Self.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            DisclosureGroup {
                                Text(item.answer)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)
                            } label: {
                                Text(item.question)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsSignUp) { SignUpFormView() }
        }
        .tint(Theme.brand)
    }

    // MARK: Content

    private static let helpDesk = "call our Help Desk on (03) 9345 6277 (Option 1 for EMR)"

    private static let sections: [FAQSection] = [
        FAQSection(title: "About My RCH Portal", items: [
            FAQItem(question: "What is My RCH Portal?", answer: """
                My RCH Portal is a patient portal with a secure mobile application and website that connects you (the patient) and your parents and legal guardians to important information about your care and treatment at the RCH, when and where it suits you.
                """),
            FAQItem(question: "Why should I sign up?", answer: """
                Using My RCH Portal is a great way to partner with your hospital teams in your care and treatment. It will make it easier for you to see and manage your hospital information. With access to your information where and when you need it, you may feel more in control of your health and more informed about your care and treatment.
                """),
            FAQItem(question: "What can I see and do?", answer: """
                When you log into My RCH Portal, you will see information about your care and treatment including upcoming appointments, medications, information about your hospital visits, some test results, allergies and details of your existing problems and diagnoses. You may also be able to view some doctors' notes, change or cancel appointments and request prescription refills.
                """),
            FAQItem(question: "Do I have to use My RCH Portal?", answer: """
                No. Signing up to My RCH Portal is completely optional. If you don't want to use the portal, you will continue to receive information about your hospital care in the same way we do today.
                """)
        ]),
        FAQSection(title: "Sign Up Questions", items: [
            FAQItem(question: "How do I sign up?", answer: """
                There are several ways to sign up for a My RCH Portal account.

                If you're a patient 12 years and older:

                1. Online sign-up form. Complete the My RCH Portal Request Form online. Upon completion of the form, your email will be used to request a copy of your photo identification, for the purpose of reviewing and processing the request. Your photo identification will be used solely to verify your identity and will not be permanently stored. We will post or text you the details to sign up for a My RCH Portal account. Please allow up to 5 business days for your request to be processed.

                2. Request an activation code. Ask for an activation code at your next hospital visit and complete the sign-up process instantly.

                If you're a parent or legal guardian:

                1. Online sign-up form (if your child is under 16 years of age). Complete the My RCH Portal Request Form online. Upon completion of the form, your email will be used to request a copy of your photo identification, for the purpose of reviewing and processing the request. Your photo identification will be used solely to verify your identity and will not be permanently stored. We will post or text you the details to sign up for a My RCH Portal account. Please allow up to 5 business days for your request to be processed.

                2. Request an activation code. Complete and return the My RCH Portal parent/legal guardian request for proxy access form at your next hospital visit or from home. You will need to provide photo identification to get an activation code.
                """),
            FAQItem(question: "Can anyone sign up?", answer: """
                No. You need to be a patient at the RCH or the parent or legal guardian of a patient to sign up to My RCH Portal. RCH patients can sign up to My RCH Portal from 12 years of age. Between the ages of 12 and 15, patients can sign up to My RCH Portal with their parents or legal guardians and share the same level of access. From 16 years of age, the young person can have sole access to My RCH Portal. Parents and legal guardians will need written consent from their child to gain access to their My RCH Portal. For patients under 12, parents and legal guardians may request proxy access to view their child's health information.
                """),
            FAQItem(question: "My activation code has expired. What should I do?", answer: """
                For your security, your activation code expires after 30 days and is no longer valid after the first time you use it. If you wish to get a new sign up code, \(helpDesk).
                """)
        ]),
        FAQSection(title: "Your Medical Information", items: [
            FAQItem(question: "What test results can I see in My RCH Portal? When?", answer: """
                My RCH Portal will automatically show you many lab test results within 4 days after they are finalised. Some test results may need to be manually released to you by your doctor or clinician. If you do not see an expected lab test result after a week, contact your care team directly. Limited imaging results are also available, but may take much longer to appear depending on processing time. If there are imaging results you are expecting but cannot view, contact the RCH or your doctor/clinician directly.
                """),
            FAQItem(question: "Can I update any of my own health information in My RCH Portal?", answer: """
                You can let your doctors or clinicians know about changes to your allergies, diagnoses and medications in My RCH Portal. These updates will flag in your record and they can be added by your doctor or clinician during your next visit. Be sure to let your doctor or clinician know of these changes during your visit.
                """),
            FAQItem(question: "What should I do if some of my health information in My RCH Portal is incorrect?", answer: """
                Speak with your doctor or clinician at your next hospital visit to alert them to the incorrect information. If they are unable to update the information, they will direct you to someone at the RCH who can.
                """),
            FAQItem(question: "Where does my health information come from?", answer: """
                The information you see in My RCH Portal comes directly from your hospital record. This record is stored securely in a single electronic system, which is used by staff at the Children's, Peter MacCallum, Royal Melbourne and the Women's hospitals involved with your clinical care.
                """),
            FAQItem(question: "Where can I update my personal information such as contact details?", answer: """
                If you are a patient, you can update some of your personal information in My RCH Portal, such as e-mail address, mobile number, your preferred name and gender identity in the Personal Information page. If there is any information which is view-only, you can request an update by opening the Message Centre and submitting a Customer Service question to your Health Service.
                """)
        ]),
        FAQSection(title: "Access for Parents & Legal Guardians", items: [
            FAQItem(question: "Can foster parents or other family members sign up to access a patient's My RCH Portal account?", answer: """
                No. For the safety and privacy of our patients, only parents and legal guardians can sign up to access their child's My RCH Portal.
                """),
            FAQItem(question: "Can I access My RCH Portal for a person in my care?", answer: """
                Yes. Parents and legal guardians can sign up for an account for a person in their care. This type of access is known as 'proxy' access and requires proof of guardianship and photo identification.
                """)
        ]),
        FAQSection(title: "Technical Questions", items: [
            FAQItem(question: "I forgot my username or password. What should I do?", answer: """
                If you're having trouble logging in, click the "Forgot Username?" or "Forgot Password?" links on the login page. You will go through two-step verification to verify your identity so you can recover your username or password for you. You can also contact our Help Desk on (03) 9345 6277 (Option 1 for EMR) for support.
                """),
            FAQItem(question: "I didn't receive my two-step verification code. What should I do?", answer: """
                If you are trying to receive your code by email, try checking your spam or junk folders. If the email with your code is not there, try using the 'Resend Code' button. If you still aren't receiving the email, \(helpDesk) for support. If we have your verified mobile number on file, you may also choose SMS method instead.
                """),
            FAQItem(question: "I was logged out of My RCH Portal. What happened?", answer: """
                We aim to protect your privacy and information. If you remain idle for 10 minutes or more after you log in to My RCH Portal, you will be automatically logged out. We recommend that you log out of My RCH Portal if you need to leave your computer for even a short period of time.
                """),
            FAQItem(question: "What do I do if I get locked out of my account?", answer: """
                If you have tried to access your account with incorrect details too many times, your account will lock to protect your health information. In this case, \(helpDesk) for assistance.
                """),
            FAQItem(question: "I have multiple My RCH Portal accounts. How do I link them together?", answer: """
                If you suspect you have multiple accounts, this might be because we have multiple medical records on file for you, or, you might have one account for your own medical information and another to access someone you care for. In all circumstances we'll need to fix this for you. You can \(helpDesk) for support.
                """),
            FAQItem(question: "How do I deactivate my account?", answer: """
                You can deactivate your own account by logging in, navigating to Account Settings in the main menu and following the 'Deactivate your account' prompts. Note that this does not delete your medical record with us, only your own access to the information. Any trusted family members with proxy access will still have access. You can still call us to reactivate your account at any time.
                """),
            FAQItem(question: "Who do I contact if I have further questions?", answer: """
                You can \(helpDesk).
                """)
        ]),
        FAQSection(title: "Other Questions", items: [
            FAQItem(question: "Is My RCH Portal different to My Health Record?", answer: """
                Yes, they are separate and different systems. The information you see through My RCH Portal comes directly from your hospital record and relates specifically to your care and treatment at any of the five hospitals across the Parkville precinct. Some of your hospital information is sent to My Health Record which is why you may see the same information in both systems.
                """),
            FAQItem(question: "How can I add another child to My RCH Portal?", answer: """
                To link another child to your existing account, complete the My RCH Portal Request Form online and select the option to add an additional child.
                """),
            FAQItem(question: "Is My RCH Portal secure?", answer: """
                We're committed to protecting your privacy and confidentiality. Our system uses the latest security technology. We will never send you emails or text messages asking for your password or login details. If you receive a suspicious email or message about your account, please do not open it. Contact our Help Desk on (03) 9345 6277 (Option 1 for EMR) to speak with our support team to confirm if it is from us.
                """),
            FAQItem(question: "After entering my date of birth during enrolment, sign-up isn't working. What should I do?", answer: """
                For security, we ask you enter your date of birth when you enrol. If you are a proxy signing up to access a patient's information, make sure you are entering your own date of birth. If you are certain that you are entering the correct date of birth, we may have it recorded incorrectly. Please contact your Health Service to review and update.
                """),
            FAQItem(question: "Can I share my account with someone?", answer: """
                No. It is a breach of privacy and security to access someone else's My RCH Portal account. Each person should have their own account secured with their own username and password. If you are caring for someone and you suspect you are accessing their account directly, please \(helpDesk).
                """),
            FAQItem(question: "Can I download and print information from my My RCH Portal account?", answer: """
                Yes. Most pages in My RCH Portal have a print icon available. If you cannot find a print icon, you can still print using your computer or phone web browser print function.
                """),
            FAQItem(question: "Why can't I see my complete or full medical record?", answer: """
                My RCH Portal displays information your Health Service, doctor or clinician have agreed to share. If you would like a copy of your full medical record, you may request it through your Health Service's Freedom of Information service. For more information, see your Health Service's website.
                """),
            FAQItem(question: "What if I can't understand my health information?", answer: """
                My RCH Portal should not replace communication with your Health Service, doctor or clinician. Your doctor or clinician will always talk to you about any test results or new information about your condition during your usual visits. If you wish to discuss any information, please contact your Health Service directly.
                """),
            FAQItem(question: "I have a My RCH Portal account and will soon be receiving treatment at the Melbourne, the Women's or Peter Mac. Do I need to also sign up to Health Hub?", answer: """
                No. You can keep your My RCH Portal account or log into Health Hub with your My RCH Portal username and password to continue to see information about your care and treatment at any of the three Parkville adult hospitals.
                """),
            FAQItem(question: "Can I use my child or dependent's activation code?", answer: """
                No. Parents and legal guardians must request their own activation code by completing the My RCH Portal Request Form online (if your child is under 16 years of age), or the paper form My RCH Portal parent/legal guardian request for proxy access.
                """)
        ])
    ]
}

#Preview {
    PortalHelpView()
}
