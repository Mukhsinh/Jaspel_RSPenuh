import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'
import { getOrSetCache } from '@/lib/utils/server-cache'

export async function GET(request: NextRequest) {
  try {
    const settings = await getOrSetCache<Record<string, any>>('t_settings:all', 10 * 60_000, async () => {
      const supabase = await createAdminClient()
      const { data, error } = await supabase
        .from('t_settings')
        .select('key, value')

      if (error) {
        throw new Error(error.message)
      }

      const result: Record<string, any> = {}
      data?.forEach((item: any) => {
        result[item.key] = item.value
      })
      return result
    })

    const response = NextResponse.json(settings)
    response.headers.set('Cache-Control', 'private, max-age=300, stale-while-revalidate=600')
    return response
  } catch (error: any) {
    console.error('Settings API exception:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
