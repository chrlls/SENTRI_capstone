import { useCallback, useEffect, useState } from 'react'
import * as api from '@/lib/api'
import { AuthContext } from '@/contexts/auth-context'

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let cancelled = false

    api.fetchCurrentUser().then((currentUser) => {
      if (!cancelled) {
        setUser(currentUser)
        setIsLoading(false)
      }
    })

    return () => {
      cancelled = true
    }
  }, [])

  const login = useCallback(async (email, password) => {
    const authenticatedUser = await api.login(email, password)
    setUser(authenticatedUser)
  }, [])

  const logout = useCallback(async () => {
    await api.logout()
    setUser(null)
  }, [])

  const value = {
    user,
    isAuthenticated: user !== null,
    isLoading,
    login,
    logout,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
