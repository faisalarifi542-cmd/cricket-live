import { Suspense } from 'react';
import { LoginForm } from '@/components/forms/LoginForm';

export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center px-4">
      <Suspense fallback={null}>
        <LoginForm />
      </Suspense>
    </main>
  );
}
