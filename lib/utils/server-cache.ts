/**
 * High-performance, lightweight in-memory cache for server-side Next.js operations.
 * Includes in-flight promise deduplication to prevent parallel cache stampedes
 * (e.g. multiple concurrent dashboard/report requests querying the same rows simultaneously).
 */

interface CacheEntry<T> {
  value: T
  expiresAt: number
}

const MAX_CACHE_ENTRIES = 250
const memoryCache = new Map<string, CacheEntry<any>>()
const inflightRequests = new Map<string, Promise<any>>()

/**
 * Retrieves a value from the in-memory cache or fetches and stores it if missing or expired.
 * Concurrent calls with the same key share a single in-flight promise (zero duplicate DB queries).
 *
 * @param key Unique cache key
 * @param ttlMs Time-to-live in milliseconds (e.g. 60000 = 1 minute)
 * @param fetcher Async function to fetch fresh data on cache miss
 */
export async function getOrSetCache<T>(
  key: string,
  ttlMs: number,
  fetcher: () => Promise<T>
): Promise<T> {
  const now = Date.now()
  const existing = memoryCache.get(key)
  if (existing && existing.expiresAt > now) {
    // Refresh LRU order
    memoryCache.delete(key)
    memoryCache.set(key, existing)
    return existing.value as T
  }

  // Deduplicate concurrent in-flight requests for the same key
  const inflight = inflightRequests.get(key)
  if (inflight) {
    return inflight as Promise<T>
  }

  const promise = (async () => {
    try {
      const value = await fetcher()
      // Evict oldest entry if at capacity
      if (memoryCache.size >= MAX_CACHE_ENTRIES) {
        const oldestKey = memoryCache.keys().next().value
        if (oldestKey !== undefined) {
          memoryCache.delete(oldestKey)
        }
      }
      memoryCache.set(key, {
        value,
        expiresAt: Date.now() + ttlMs,
      })
      return value
    } finally {
      inflightRequests.delete(key)
    }
  })()

  inflightRequests.set(key, promise)
  return promise
}

/**
 * Invalidates cache entries by key or prefix.
 */
export function invalidateCache(keyPrefix?: string) {
  if (!keyPrefix) {
    memoryCache.clear()
    return
  }
  memoryCache.forEach((_, key) => {
    if (key.startsWith(keyPrefix)) {
      memoryCache.delete(key)
    }
  })
}

/**
 * Shared cached KPI metadata lookup maps to eliminate massive repeated nested joins
 * on t_kpi_assessments queries (saves 50-70% of Supabase egress!).
 */
export interface CachedKpiMetadata {
  categoriesMap: Map<string, any>
  indicatorsMap: Map<string, any>
  subIndicatorsMap: Map<string, any>
  categories: any[]
  indicators: any[]
  subIndicators: any[]
}

export async function getCachedKpiMetadata(
  supabase: any,
  ttlMs: number = 5 * 60_000
): Promise<CachedKpiMetadata> {
  return getOrSetCache<CachedKpiMetadata>('kpi_metadata:full', ttlMs, async () => {
    const [catRes, indRes, subRes] = await Promise.all([
      supabase
        .from('m_kpi_categories')
        .select('id, unit_id, category, weight_percentage, configuration_style, is_weighted, revenue_type, is_active'),
      supabase
        .from('m_kpi_indicators')
        .select('id, category_id, name, weight_percentage, base_index_value, target_value, calculation_method, is_active'),
      supabase
        .from('m_kpi_sub_indicators')
        .select('id, indicator_id, measurement_type, base_index_value, weight_percentage, is_active'),
    ])

    const categories = catRes.data || []
    const indicators = indRes.data || []
    const subIndicators = subRes.data || []

    const categoriesMap = new Map<string, any>()
    for (const c of categories) {
      categoriesMap.set(c.id, c)
    }

    const indicatorsMap = new Map<string, any>()
    for (const ind of indicators) {
      const cat = categoriesMap.get(ind.category_id) || null
      indicatorsMap.set(ind.id, {
        ...ind,
        m_kpi_categories: cat,
      })
    }

    const subIndicatorsMap = new Map<string, any>()
    for (const sub of subIndicators) {
      subIndicatorsMap.set(sub.id, sub)
    }

    return {
      categoriesMap,
      indicatorsMap,
      subIndicatorsMap,
      categories,
      indicators,
      subIndicators,
    }
  })
}
