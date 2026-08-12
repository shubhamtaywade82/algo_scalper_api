import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Algo-Scalper Architecture Dashboard',
  description: 'Live architecture visualization for algo_scalper_api',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="bg-[#09090b] text-zinc-100 antialiased">
        {children}
      </body>
    </html>
  );
}
