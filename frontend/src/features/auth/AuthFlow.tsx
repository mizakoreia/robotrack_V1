import React, { useState } from 'react'
import { MagicLogin } from './MagicLogin'
import { CodeValidation } from './CodeValidation'
import { CompleteRegistration } from './CompleteRegistration'
import { useAuthStore } from '@/store/authStore'

type AuthStep = 'login' | 'code' | 'complete'

export const AuthFlow: React.FC = () => {
  const [currentStep, setCurrentStep] = useState<AuthStep>('login')
  const { identifier } = useAuthStore()

  const handleCodeSent = () => {
    setCurrentStep('code')
  }

  const handleBackToLogin = () => {
    setCurrentStep('login')
  }

  const handleCodeVerified = () => {
    setCurrentStep('complete')
  }

  return (
    <>
      {currentStep === 'login' && (
        <MagicLogin onCodeSent={handleCodeSent} />
      )}
      
      {currentStep === 'code' && identifier && (
        <CodeValidation 
          email={identifier} 
          onBack={handleBackToLogin} 
          onSuccess={handleCodeVerified} 
        />
      )}

      {currentStep === 'complete' && (
        <CompleteRegistration onBack={() => setCurrentStep('login')} />
      )}
    </>
  )
}
