# Auth email templates

`recovery.html` is the password-reset email, live on the project under
Auth > Email Templates > Reset password. Arabic first, then English, around
one 6-digit code (`{{ .Token }}`) that the app asks for after "Forgot
password", plus a button for opening the link on the same device.

Subject:

    {{ .Token }} كود إعادة تعيين كلمة السر · Password reset code

The code leads the subject so it can be read straight off the notification.

To change it, edit this file and push it with the Management API
(`PATCH /v1/projects/{ref}/config/auth`, fields `mailer_subjects_recovery`
and `mailer_templates_recovery_content`) or paste it into the dashboard.
Templates only take effect while a custom SMTP provider is configured.
