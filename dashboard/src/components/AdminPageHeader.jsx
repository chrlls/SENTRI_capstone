import { useLocation } from 'react-router-dom'
import { findActiveAdminNavItem } from '@/lib/adminNav'

/** Plain page title, sourced from the same adminNav config the sidebar renders — sits in page content, between AdminHeader's search bar and whatever the page renders below it. */
export function AdminPageHeader() {
  const location = useLocation()
  const activeItem = findActiveAdminNavItem(location.pathname)

  return <h1 className="font-heading text-2xl font-semibold text-foreground">{activeItem.label}</h1>
}
