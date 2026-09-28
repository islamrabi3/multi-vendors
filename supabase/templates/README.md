# Auth email templates

`recovery.html` is the password-reset email: a 6-digit code (`{{ .Token }}`) that
the app asks for after "Forgot password", plus the link for opening it on the
same device. English and Arabic.

Supabase refuses template changes on the free tier while the built-in mailer
is in use, so this is not live yet. Once a custom SMTP provider is set under
Auth > SMTP Settings, paste this file into Auth > Email Templates > Reset
password, with the subject:

    Your password reset code / كود إعادة تعيين كلمة السر
