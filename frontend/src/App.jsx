import React, { useEffect, useState } from 'react'

export default function App() {
  const [msg, setMsg] = useState('...')

  useEffect(() => {
    fetch('/api/hello')
      .then(r => r.json())
      .then(d => setMsg(d.message))
      .catch(() => setMsg('Error consultando backend'))
  }, [])

  return (
    <main style={{fontFamily:'system-ui, sans-serif', display:'grid', placeItems:'center', minHeight:'100vh'}}>
      <div>
        <h1>Frontend: Hola mundo 👋</h1>
        <p>Backend dice: <strong>{msg}</strong></p>
      </div>
    </main>
  )
}