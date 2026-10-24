'use client';

import * as React from 'react';

const TooltipContext = React.createContext<{ isOpen: boolean; onOpen: () => void; onClose: () => void; triggerEl: HTMLElement | null }>({ isOpen: false, onOpen: () => {}, onClose: () => {}, triggerEl: null });

function TooltipProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = React.useState({ isOpen: false, triggerEl: null as HTMLElement | null });
  const onOpen = React.useCallback(() => setState(s => ({ ...s, isOpen: true })), []);
  const onClose = React.useCallback(() => setState(s => ({ ...s, isOpen: false })), []);
  return (
    <TooltipContext.Provider value={{ ...state, onOpen, onClose }}>
      {children}
    </TooltipContext.Provider>
  );
}

function TooltipTrigger({ children, asChild, ...props }: { children: React.ReactNode; asChild?: boolean } & React.HTMLAttributes<HTMLDivElement>) {
  const ctx = React.useContext(TooltipContext);
  const ref = React.useRef<HTMLDivElement>(null);
  const handleEnter = () => {
    ctx.onOpen();
    if (ref.current) {
      (ctx as { triggerEl: HTMLElement | null }).triggerEl = ref.current;
    }
  };
  if (asChild && React.isValidElement(children)) {
    return React.cloneElement(children as React.ReactElement<{ onMouseEnter?: () => void; ref?: React.Ref<HTMLDivElement> }>, { onMouseEnter: handleEnter, ref });
  }
  return <div ref={ref} onMouseEnter={handleEnter} onMouseLeave={ctx.onClose} {...props}>{children}</div>;
}

function TooltipContent({ children, className, ...props }: { children: React.ReactNode; className?: string; side?: string } & React.HTMLAttributes<HTMLDivElement>) {
  const ctx = React.useContext(TooltipContext);
  if (!ctx.isOpen) return null;
  return (
    <div
      className={`absolute z-50 rounded-md bg-zinc-800 px-3 py-1.5 text-xs text-zinc-200 shadow-md border border-zinc-700 max-w-xs ${className || ''}`}
      onMouseLeave={ctx.onClose}
      {...props}
    >
      {children}
    </div>
  );
}

function Tooltip({ children, ...props }: { children: React.ReactNode; side?: string } & React.HTMLAttributes<HTMLDivElement>) {
  return <TooltipProvider>{children}</TooltipProvider>;
}

export { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider };
