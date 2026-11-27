'use client'

import { useEffect, useState, useRef, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Clock, ShieldAlert, ArrowRight, LogOut } from 'lucide-react'
import { clearAuthStorage } from '@/lib/utils/auth-session'

// Inactivity threshold: 30 minutes
const INACTIVITY_TIMEOUT_MS = 30 * 60 * 1000
// Warning threshold: 2 minutes before timeout (at 28 minutes of inactivity)
const WARNING_THRESHOLD_MS = 2 * 60 * 1000
// Grace countdown duration when returning to an inactive tab (60 seconds)
const GRACE_PERIOD_SECONDS = 60
// Throttle activity recording to at most once every 5 seconds
const ACTIVITY_THROTTLE_MS = 5000
// Coarse check interval while active (30s) — only switches to 1s when warning dialog is open
const IDLE_CHECK_INTERVAL_MS = 30 * 1000
const STORAGE_KEY = 'jaspel_last_active_time'
const LOGOUT_SYNC_KEY = 'jaspel_logout_event'

// Lightweight passive interaction events (no mousemove/scroll flood)
const INTERACTION_EVENTS: (keyof WindowEventMap)[] = [
  'pointerdown',
  'keydown',
  'wheel',
  'touchstart',
]

export default function SessionActivityManager() {
  const [showWarning, setShowWarning] = useState(false)
  const [secondsRemaining, setSecondsRemaining] = useState(120)
  const lastActivityRef = useRef<number>(Date.now())
  const isLoggingOutRef = useRef<boolean>(false)
  const graceCountdownRef = useRef<number | null>(null)

  const getStoredActivityTime = useCallback((): number => {
    if (typeof window === 'undefined') return Date.now()
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored) {
        const parsed = parseInt(stored, 10)
        const now = Date.now()
        if (!isNaN(parsed) && parsed > 0 && parsed <= now && (now - parsed) < INACTIVITY_TIMEOUT_MS) {
          return parsed
        }
      }
    } catch {
      // fallback
    }
    const now = Date.now()
    try {
      localStorage.setItem(STORAGE_KEY, now.toString())
    } catch {}
    return now
  }, [])

  const recordActivity = useCallback(() => {
    if (isLoggingOutRef.current) return
    const now = Date.now()
    if (now - lastActivityRef.current < ACTIVITY_THROTTLE_MS) return

    lastActivityRef.current = now
    graceCountdownRef.current = null
    try {
      localStorage.setItem(STORAGE_KEY, now.toString())
    } catch {}

    setShowWarning(prev => (prev ? false : prev))
  }, [])

  const performLogout = useCallback(async () => {
    if (isLoggingOutRef.current) return
    isLoggingOutRef.current = true

    try {
      if (typeof window !== 'undefined') {
        localStorage.removeItem(STORAGE_KEY)
        try {
          localStorage.setItem(LOGOUT_SYNC_KEY, Date.now().toString())
        } catch {}
        clearAuthStorage(true)

        const supabase = createClient()
        await supabase.auth.signOut({ scope: 'local' }).catch(() => {})

        window.location.href = '/login?reason=idle_timeout'
      }
    } catch {
      window.location.href = '/login?reason=idle_timeout'
    }
  }, [])

  const handleContinueSession = useCallback(() => {
    const now = Date.now()
    lastActivityRef.current = now
    graceCountdownRef.current = null
    try {
      localStorage.setItem(STORAGE_KEY, now.toString())
    } catch {}
    setShowWarning(false)
  }, [])

  const formatTime = (totalSeconds: number) => {
    const mins = Math.floor(totalSeconds / 60)
    const secs = totalSeconds % 60
    return mins > 0 ? `${mins} menit ${secs} detik` : `${secs} detik`
  }

  // Lightweight activity listeners + coarse 30s idle check (no window.fetch monkey-patch, no duplicate autoRefresh)
  useEffect(() => {
    const now = Date.now()
    lastActivityRef.current = now
    try {
      localStorage.setItem(STORAGE_KEY, now.toString())
    } catch {}

    const handleEvent = () => recordActivity()
    INTERACTION_EVENTS.forEach(event => {
      window.addEventListener(event, handleEvent, { capture: true, passive: true })
    })

    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY && e.newValue) {
        const newTime = parseInt(e.newValue, 10)
        if (!isNaN(newTime) && newTime > lastActivityRef.current) {
          lastActivityRef.current = newTime
          graceCountdownRef.current = null
          setShowWarning(false)
        }
      } else if (e.key === LOGOUT_SYNC_KEY && e.newValue) {
        performLogout()
      }
    }
    window.addEventListener('storage', handleStorageChange)

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        const storedTime = getStoredActivityTime()
        lastActivityRef.current = Math.max(lastActivityRef.current, storedTime)
        const idleTime = Date.now() - lastActivityRef.current

        if (idleTime >= INACTIVITY_TIMEOUT_MS) {
          if (graceCountdownRef.current === null) {
            graceCountdownRef.current = GRACE_PERIOD_SECONDS
            setSecondsRemaining(GRACE_PERIOD_SECONDS)
            setShowWarning(true)
          }
        } else {
          recordActivity()
        }
      }
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)

    const idleInterval = setInterval(() => {
      if (isLoggingOutRef.current || graceCountdownRef.current !== null) return

      const currentTime = Date.now()
      const storedTime = getStoredActivityTime()
      const effectiveLastActivity = Math.max(lastActivityRef.current, storedTime)
      const idleTime = currentTime - effectiveLastActivity

      if (idleTime >= INACTIVITY_TIMEOUT_MS) {
        performLogout()
        return
      }

      const warningWindowStart = INACTIVITY_TIMEOUT_MS - WARNING_THRESHOLD_MS
      if (idleTime >= warningWindowStart) {
        const remainingSec = Math.max(1, Math.ceil((INACTIVITY_TIMEOUT_MS - idleTime) / 1000))
        setSecondsRemaining(remainingSec)
        setShowWarning(true)
      }
    }, IDLE_CHECK_INTERVAL_MS)

    return () => {
      INTERACTION_EVENTS.forEach(event => {
        window.removeEventListener(event, handleEvent, { capture: true })
      })
      window.removeEventListener('storage', handleStorageChange)
      document.removeEventListener('visibilitychange', handleVisibilityChange)
      clearInterval(idleInterval)
    }
  }, [getStoredActivityTime, recordActivity, performLogout])

  // Fine-grained 1-second countdown ONLY while warning dialog is actually visible
  useEffect(() => {
    if (!showWarning) return

    const countdownInterval = setInterval(() => {
      if (isLoggingOutRef.current) return

      if (graceCountdownRef.current !== null) {
        const nextGrace = graceCountdownRef.current - 1
        graceCountdownRef.current = nextGrace
        setSecondsRemaining(Math.max(0, nextGrace))
        if (nextGrace <= 0) {
          clearInterval(countdownInterval)
          performLogout()
        }
        return
      }

      const idleTime = Date.now() - Math.max(lastActivityRef.current, getStoredActivityTime())
      if (idleTime >= INACTIVITY_TIMEOUT_MS) {
        clearInterval(countdownInterval)
        performLogout()
        return
      }

      const remainingSec = Math.max(1, Math.ceil((INACTIVITY_TIMEOUT_MS - idleTime) / 1000))
      setSecondsRemaining(remainingSec)
    }, 1000)

    return () => clearInterval(countdownInterval)
  }, [showWarning, getStoredActivityTime, performLogout])

  if (!showWarning) return null

  return (
    <Dialog open={showWarning} onOpenChange={(open) => {
      if (!open) {
        handleContinueSession()
      }
    }}>
      <DialogContent className="sm:max-w-[460px] p-6 bg-white dark:bg-slate-900 border border-amber-200 dark:border-amber-900/50 shadow-2xl rounded-2xl z-[9999]">
        <DialogHeader className="space-y-3">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-100 text-amber-600 dark:bg-amber-950/60 dark:text-amber-400 shadow-inner">
            <Clock className="h-7 w-7 animate-pulse text-amber-600" />
          </div>
          <DialogTitle className="text-center text-xl font-bold text-gray-900 dark:text-gray-100">
            Pemberitahuan Inaktivitas Sesi
          </DialogTitle>
          <DialogDescription className="text-center text-sm text-gray-600 dark:text-gray-400 leading-relaxed">
            Tidak ada aktivitas terdeteksi selama hampir 30 menit. Sesi Anda akan berakhir secara otomatis dalam:
          </DialogDescription>
        </DialogHeader>

        <div className="my-3 py-3 px-4 rounded-xl bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800/40 flex items-center justify-center gap-3">
          <ShieldAlert className="h-5 w-5 text-amber-600 dark:text-amber-400 animate-bounce" />
          <span className="text-2xl font-black text-amber-700 dark:text-amber-300 font-mono tracking-wider">
            {formatTime(secondsRemaining)}
          </span>
        </div>

        <p className="text-xs text-center text-gray-500 dark:text-gray-400">
          Klik tombol di bawah atau lakukan aktivitas untuk memperpanjang sesi dan tetap masuk.
        </p>

        <DialogFooter className="mt-4 flex flex-col sm:flex-row gap-2">
          <Button
            type="button"
            variant="outline"
            onClick={performLogout}
            className="w-full sm:w-auto text-gray-600 hover:text-gray-800 border-gray-300"
          >
            <LogOut className="h-4 w-4 mr-2" />
            Keluar Sekarang
          </Button>
          <Button
            type="button"
            onClick={handleContinueSession}
            className="w-full sm:flex-1 bg-blue-600 hover:bg-blue-700 text-white font-semibold shadow-md shadow-blue-500/20"
          >
            Lanjutkan Sesi
            <ArrowRight className="h-4 w-4 ml-2" />
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
