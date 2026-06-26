import Foundation

extension LauncherStore {
    func beginAddingAccount() async {
        showAccountLogin()
        await beginQRLogin()
    }

    func showAccountLogin() {
        loginFormPresented = true
    }

    func startQRLoginAttempt() -> Int {
        qrLoginAttempt += 1
        return qrLoginAttempt
    }

    func applyQRSession(_ session: QRSession, attempt: Int) -> Bool {
        guard attempt == qrLoginAttempt else { return false }
        if qrSession == nil, session.status == "expired" { return false }
        qrSession = session
        return true
    }

    func finishQRLoginAttempt(_ attempt: Int) {
        guard attempt == qrLoginAttempt else { return }
        qrLoginAttempt += 1
        qrSession = nil
        loginFormPresented = false
    }

    func mobileVerification(from error: APIErrorPayload) -> MobileCaptchaVerificationContext? {
        guard let details = error.details,
              let gt = details["gt"],
              let challenge = details["challenge"],
              let sessionId = details["session_id"] ?? details["sessionId"] else {
            return nil
        }
        return MobileCaptchaVerificationContext(
            mobile: loginMobile,
            verification: MobileCaptchaVerification(gt: gt, challenge: challenge, sessionId: sessionId)
        )
    }
}
