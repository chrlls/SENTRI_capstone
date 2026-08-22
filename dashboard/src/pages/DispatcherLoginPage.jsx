import { useId, useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { AuthError } from '@/lib/api'

const EMAIL_PATTERN = /^\S+@\S+\.\S+$/

// Plain CSS (not Tailwind) on purpose: the floating-label/underline pattern
// below depends on sibling combinators (`:focus + label`, `~ .underline`)
// and forced-state compound selectors (`.field.err .label`) that Tailwind
// utilities can't express, and shadcn's Input/Label fight the animation.
// Classes are prefixed to avoid colliding with any other global CSS in the app.
const CSS = `
.sentri-login-page {
  min-height: 100vh;
  width: 100%;
  background: #0b0d13;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.sentri-login-stage {
  width: 100%;
  max-width: 340px;
  display: flex;
  flex-direction: column;
  align-items: center;
  animation: sentri-login-rise 0.6s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes sentri-login-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.sentri-login-heading {
  font-size: 26px;
  font-weight: 300;
  color: #f3f5f8;
  letter-spacing: 0.01em;
  margin-bottom: 4px;
}

.sentri-login-sub {
  font-size: 12.5px;
  color: #565f70;
  margin-bottom: 44px;
  text-align: center;
}

.sentri-login-form {
  width: 100%;
}

.sentri-login-field {
  width: 100%;
  margin-bottom: 28px;
  position: relative;
}

.sentri-login-label {
  position: absolute;
  left: 2px;
  top: 9px;
  font-size: 14.5px;
  color: #4a5266;
  pointer-events: none;
  transform-origin: left top;
  transition:
    transform 0.25s cubic-bezier(0.16, 1, 0.3, 1),
    color 0.25s ease;
}

.sentri-login-input {
  width: 100%;
  background: transparent;
  border: none;
  border-bottom: 1px solid #232838;
  padding: 8px 2px 10px;
  font-size: 14.5px;
  color: #f3f5f8;
  outline: none;
  font-family: inherit;
  transition: border-color 0.35s cubic-bezier(0.16, 1, 0.3, 1);
}

.sentri-login-input::placeholder {
  color: transparent;
}

.sentri-login-input:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.sentri-login-password-input {
  padding-right: 28px;
}

.sentri-login-input:focus + .sentri-login-label,
.sentri-login-field.filled .sentri-login-label {
  transform: translateY(-22px) scale(0.78);
  color: #6e93d6;
}

.sentri-login-underline {
  position: absolute;
  bottom: 0;
  left: 0;
  height: 1px;
  width: 0%;
  background: #4c8df5;
  transition: width 0.35s cubic-bezier(0.16, 1, 0.3, 1);
}

.sentri-login-input:focus ~ .sentri-login-underline,
.sentri-login-field.filled .sentri-login-underline {
  width: 100%;
}

.sentri-login-input.err {
  border-color: #c15353;
}

.sentri-login-field.err .sentri-login-label {
  color: #c15353;
  transform: translateY(-22px) scale(0.78);
}

.sentri-login-field.err .sentri-login-underline {
  background: #c15353;
  width: 100%;
}

.sentri-login-toggle-pw {
  position: absolute;
  right: 2px;
  top: 6px;
  background: none;
  border: none;
  color: #4a5266;
  cursor: pointer;
  padding: 4px;
  display: flex;
  line-height: 0;
  transition: color 0.2s ease;
}

.sentri-login-toggle-pw:hover {
  color: #8a93a6;
}

.sentri-login-toggle-pw:disabled {
  pointer-events: none;
  opacity: 0.6;
}

.sentri-login-form-err {
  font-size: 11px;
  color: #d18585;
  margin: -16px 0 16px;
  text-align: left;
}

.sentri-login-signin-btn {
  width: 100%;
  background: transparent;
  border: 1px solid #263047;
  color: #dce2ed;
  border-radius: 6px;
  padding: 12px;
  font-size: 13px;
  font-weight: 500;
  letter-spacing: 0.06em;
  font-family: inherit;
  cursor: pointer;
  margin-top: 8px;
  transition:
    background 0.25s ease,
    border-color 0.25s ease,
    transform 0.1s ease;
}

.sentri-login-signin-btn:hover {
  background: rgba(76, 141, 245, 0.08);
  border-color: #3b5a8a;
}

.sentri-login-signin-btn:active {
  transform: scale(0.99);
}

.sentri-login-signin-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  transform: none;
}
`

function cx(...classNames) {
  return classNames.filter(Boolean).join(' ')
}

function EyeIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  )
}

function EyeOffIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M17.94 17.94A10.94 10.94 0 0 1 12 19c-7 0-11-7-11-7a18.36 18.36 0 0 1 4.22-5.06M9.9 4.24A10.94 10.94 0 0 1 12 4c7 0 11 7 11 7a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  )
}

export function DispatcherLoginPage() {
  const { login } = useAuth()
  const emailId = useId()
  const passwordId = useId()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [formError, setFormError] = useState(null)
  const [fieldErrors, setFieldErrors] = useState({ email: false, password: false })

  function handleEmailChange(event) {
    setEmail(event.target.value)
    setFieldErrors((prev) => (prev.email ? { ...prev, email: false } : prev))
  }

  function handlePasswordChange(event) {
    setPassword(event.target.value)
    setFieldErrors((prev) => (prev.password ? { ...prev, password: false } : prev))
  }

  async function handleSubmit(event) {
    event.preventDefault()

    const emailOk = EMAIL_PATTERN.test(email.trim())
    const passwordOk = password !== ''

    const nextFieldErrors = { email: !emailOk, password: !passwordOk }
    setFieldErrors(nextFieldErrors)
    if (nextFieldErrors.email || nextFieldErrors.password) {
      return
    }

    setFormError(null)
    setIsSubmitting(true)

    try {
      await login(email, password)
    } catch (err) {
      // Generic on purpose: never tell the caller whether the email or the
      // password was the wrong part of the pair.
      setFormError(
        err instanceof AuthError
          ? err.message
          : 'Unable to reach the server. Check your connection and try again.',
      )
    } finally {
      setIsSubmitting(false)
    }
  }

  const emailFilled = email.length > 0
  const passwordFilled = password.length > 0

  return (
    <div className="sentri-login-page">
      <style>{CSS}</style>
      <div className="sentri-login-stage">
        <h1 className="sentri-login-heading">Welcome</h1>
        <p className="sentri-login-sub">Sign in to your account</p>

        <form className="sentri-login-form" onSubmit={handleSubmit} noValidate>
          <div className={cx('sentri-login-field', emailFilled && 'filled', fieldErrors.email && 'err')}>
            <input
              id={emailId}
              type="email"
              placeholder="Email"
              autoComplete="email"
              value={email}
              onChange={handleEmailChange}
              disabled={isSubmitting}
              className={cx('sentri-login-input', fieldErrors.email && 'err')}
            />
            <label htmlFor={emailId} className="sentri-login-label">
              Email
            </label>
            <div className="sentri-login-underline" />
          </div>

          <div className={cx('sentri-login-field', passwordFilled && 'filled', fieldErrors.password && 'err')}>
            <input
              id={passwordId}
              type={showPassword ? 'text' : 'password'}
              placeholder="Password"
              autoComplete="current-password"
              value={password}
              onChange={handlePasswordChange}
              disabled={isSubmitting}
              className={cx('sentri-login-input', 'sentri-login-password-input', fieldErrors.password && 'err')}
            />
            <label htmlFor={passwordId} className="sentri-login-label">
              Password
            </label>
            <div className="sentri-login-underline" />
            <button
              type="button"
              className="sentri-login-toggle-pw"
              onClick={() => setShowPassword((visible) => !visible)}
              disabled={isSubmitting}
              aria-label={showPassword ? 'Hide password' : 'Show password'}
            >
              {showPassword ? <EyeOffIcon /> : <EyeIcon />}
            </button>
          </div>

          {formError !== null && <p className="sentri-login-form-err">{formError}</p>}

          <button type="submit" className="sentri-login-signin-btn" disabled={isSubmitting}>
            {isSubmitting ? 'Signing in…' : 'Login'}
          </button>
        </form>
      </div>
    </div>
  )
}
