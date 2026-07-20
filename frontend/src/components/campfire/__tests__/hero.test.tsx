import React from 'react'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom'
import { HeroCampfire } from '../HeroCampfire'

describe('HeroCampfire', () => {
  it('renders headline and CTAs', () => {
    render(<HeroCampfire />)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(/Crie e lance/i)
    expect(screen.getByText(/Pagamento rápido/i)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Ver planos/i })).toHaveAttribute('href', '#plans')
  })
})

