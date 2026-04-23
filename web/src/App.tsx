import type { ReactNode } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './auth/AuthContext'
import { Layout } from './components/Layout'
import { ProtectedRoute } from './components/ProtectedRoute'
import { CalendarPage } from './pages/CalendarPage'
import { ClosetPage } from './pages/ClosetPage'
import { LoginPage } from './pages/LoginPage'
import { OutfitsPage } from './pages/OutfitsPage'

function HomeRedirect() {
  const { isAuthenticated } = useAuth()
  return <Navigate to={isAuthenticated ? '/closet' : '/login'} replace />
}

function authedPage(page: ReactNode) {
  return (
    <ProtectedRoute>
      <Layout>{page}</Layout>
    </ProtectedRoute>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/" element={<HomeRedirect />} />
        <Route path="/closet" element={authedPage(<ClosetPage />)} />
        <Route path="/outfits" element={authedPage(<OutfitsPage />)} />
        <Route path="/calendar" element={authedPage(<CalendarPage />)} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
