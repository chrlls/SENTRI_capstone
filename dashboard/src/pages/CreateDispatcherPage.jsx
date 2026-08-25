import { useId, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { DispatcherHeader } from '@/components/DispatcherHeader'
import { ApiError, createDispatcher } from '@/lib/api'

export function CreateDispatcherPage() {
  const navigate = useNavigate()
  const emailId = useId()
  const phoneId = useId()
  const passwordId = useId()
  const fullNameId = useId()

  const [email, setEmail] = useState('')
  const [phoneNumber, setPhoneNumber] = useState('')
  const [password, setPassword] = useState('')
  const [fullName, setFullName] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [error, setError] = useState(null)
  const [created, setCreated] = useState(null)

  async function handleSubmit(event) {
    event.preventDefault()
    setError(null)
    setIsSubmitting(true)

    try {
      const user = await createDispatcher({ email, phoneNumber, password, fullName })
      setCreated(user)
      setEmail('')
      setPhoneNumber('')
      setPassword('')
      setFullName('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to reach the server. Check your connection and try again.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="flex h-svh flex-col bg-background">
      <DispatcherHeader />
      <div className="flex items-center gap-2 border-b border-border px-4 py-2">
        <Button variant="ghost" size="sm" onClick={() => navigate('/')}>
          <ArrowLeft /> Back to queue
        </Button>
      </div>

      <div className="flex flex-1 items-start justify-center overflow-y-auto p-6">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Create dispatcher account</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            {created !== null && (
              <Alert>
                <AlertDescription>
                  Dispatcher account created — share the password with them directly.
                </AlertDescription>
              </Alert>
            )}

            {error !== null && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <form className="flex flex-col gap-4" onSubmit={handleSubmit}>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor={fullNameId}>Full name</Label>
                <Input
                  id={fullNameId}
                  value={fullName}
                  onChange={(event) => setFullName(event.target.value)}
                  disabled={isSubmitting}
                  required
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor={emailId}>Email</Label>
                <Input
                  id={emailId}
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  disabled={isSubmitting}
                  required
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor={phoneId}>Phone number</Label>
                <Input
                  id={phoneId}
                  type="tel"
                  value={phoneNumber}
                  onChange={(event) => setPhoneNumber(event.target.value)}
                  disabled={isSubmitting}
                  required
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor={passwordId}>Password</Label>
                <Input
                  id={passwordId}
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  disabled={isSubmitting}
                  required
                  minLength={8}
                />
              </div>

              <Button type="submit" disabled={isSubmitting}>
                {isSubmitting ? 'Creating…' : 'Create dispatcher'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
