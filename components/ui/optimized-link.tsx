'use client'

import Link from 'next/link'
import { forwardRef } from 'react'
import { cn } from '@/lib/utils'

interface OptimizedLinkProps extends React.ComponentProps<typeof Link> {
  className?: string
  children: React.ReactNode
  prefetch?: boolean
}

/**
 * OptimizedLink component - Next.js Link wrapper
 * Defaults to prefetch={false} to prevent Next.js from eagerly executing heavy
 * dynamic Server Component routes (e.g. /dashboard, /assessment) in the background
 * on every page load, which dramatically reduces Supabase egress.
 */
const OptimizedLink = forwardRef<HTMLAnchorElement, OptimizedLinkProps>(
  ({ className, children, prefetch = false, ...props }, ref) => {
    return (
      <Link
        ref={ref}
        prefetch={prefetch}
        className={cn(className)}
        {...props}
      >
        {children}
      </Link>
    )
  }
)

OptimizedLink.displayName = 'OptimizedLink'

export { OptimizedLink }