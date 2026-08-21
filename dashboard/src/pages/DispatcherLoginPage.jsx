import { useId, useState } from 'react'
import { Eye, EyeOff, Loader2, MapPin, ShieldAlert, ShieldCheck, TriangleAlert, Users } from 'lucide-react'
import { useAuth } from '@/hooks/use-auth'
import { AuthError } from '@/lib/api'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

// Imported as a module (not referenced as a bare /public path) so Vite
// fingerprints/optimizes it.
import dispatchSkyline from '@/assets/dispatch-skyline.png'

const BRAND_FEATURES = [
  {
    icon: MapPin,
    title: 'Live Incident Monitoring',
    description: 'Track and visualize incidents as they happen.',
    tint: 'text-primary bg-primary/10',
  },
  {
    icon: Users,
    title: 'Coordinated Response',
    description: 'Dispatch responders and track their real-time status.',
    tint: 'text-sky-400 bg-sky-400/10',
  },
  {
    icon: ShieldCheck,
    title: 'Community Safety',
    description: 'Data-driven insights for a safer, more secure community.',
    tint: 'text-emerald-400 bg-emerald-400/10',
  },
]

export function DispatcherLoginPage() {
  const { login } = useAuth()
  const emailId = useId()
  const passwordId = useId()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [error, setError] = useState(null)

  async function handleSubmit(event) {
    event.preventDefault()
    setError(null)
    setIsSubmitting(true)

    try {
      await login(email, password)
    } catch (err) {
      setError(
        err instanceof AuthError
          ? err.message
          : 'Unable to reach the server. Check your connection and try again.',
      )
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="grid min-h-svh bg-background lg:grid-cols-2">
      {/* Branding panel — hidden below lg, since a background image
          fighting for space with a login form doesn't work on mobile */}
      <div className="relative hidden overflow-hidden lg:flex lg:flex-col lg:justify-between lg:p-12">
        <img
          src={dispatchSkyline}
          alt=""
          role="presentation"
          className="absolute inset-0 size-full object-cover"
        />
        {/* Scrim: darkens the photo so white text stays readable
            everywhere, independent of what's underneath it */}
        <div className="absolute inset-0 bg-gradient-to-t from-background via-background/70 to-background/20" />

        <div className="relative z-10 flex items-center gap-3">
          <div className="flex size-11 items-center justify-center rounded-xl border border-primary/40 bg-primary/15 text-primary">
            <ShieldAlert className="size-6" />
          </div>
          <div>
            <div className="text-xl font-bold tracking-tight text-white">SENTRI</div>
            <div className="text-xs font-medium tracking-widest text-white/60 uppercase">
              Emergency Response System
            </div>
          </div>
        </div>

        <div className="relative z-10 flex flex-col gap-8">
          <div className="flex flex-col gap-2">
            <h1 className="text-3xl font-bold text-white">
              Intelligent. Connected. Prepared.
            </h1>
            <p className="max-w-sm text-white/70">
              Real-time monitoring, rapid response, safer communities.
            </p>
          </div>

          <ul className="flex flex-col gap-5">
            {BRAND_FEATURES.map(({ icon: Icon, title, description, tint }) => (
              <li key={title} className="flex items-start gap-3.5">
                <div className={`flex size-9 shrink-0 items-center justify-center rounded-lg ${tint}`}>
                  <Icon className="size-4.5" />
                </div>
                <div>
                  <div className="text-sm font-semibold text-white">{title}</div>
                  <div className="text-sm text-white/60">{description}</div>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="relative z-10 text-xs text-white/40">
          © {new Date().getFullYear()} SENTRI Emergency Response System. All rights reserved.
        </div>
      </div>

      {/* Login panel — unchanged logic from here down, only the
          outer wrapper changed (was: centered card on full width) */}
      <div className="flex items-center justify-center px-4 py-12">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <div className="mb-1 flex items-center gap-2 text-primary lg:hidden">
              <ShieldAlert className="size-5" />
              <span className="text-xs font-semibold tracking-widest uppercase">SENTRI</span>
            </div>
            <CardTitle className="text-lg">Dispatcher Console</CardTitle>
            <CardDescription>Sign in with your provisioned PNP or admin account.</CardDescription>
          </CardHeader>

          <CardContent>
            <form className="flex flex-col gap-4" onSubmit={handleSubmit} noValidate>
              {error !== null && (
                <Alert variant="destructive">
                  <TriangleAlert />
                  <AlertTitle>Sign-in failed</AlertTitle>
                  <AlertDescription>{error}</AlertDescription>
                </Alert>
              )}

              <div className="flex flex-col gap-1.5">
                <Label htmlFor={emailId}>Email</Label>
                <Input
                  id={emailId}
                  type="email"
                  autoComplete="username"
                  required
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  disabled={isSubmitting}
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor={passwordId}>Password</Label>
                <div className="relative">
                  <Input
                    id={passwordId}
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    required
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    disabled={isSubmitting}
                    className="pr-9"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((visible) => !visible)}
                    disabled={isSubmitting}
                    className="absolute inset-y-0 right-0 flex w-9 items-center justify-center text-muted-foreground hover:text-foreground disabled:pointer-events-none disabled:opacity-50"
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                  >
                    {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                  </button>
                </div>
              </div>

              <Button type="submit" disabled={isSubmitting} className="mt-1">
                {isSubmitting && <Loader2 className="animate-spin" />}
                {isSubmitting ? 'Signing in…' : 'Sign in'}
              </Button>
            </form>
          </CardContent>

          <CardFooter className="text-xs text-muted-foreground">
            Dispatcher access is provisioned by a system administrator. There is
            no self-service registration for this console.
          </CardFooter>
        </Card>
      </div>
    </div>
  )
}
