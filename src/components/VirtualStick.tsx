import React, { useRef, useState } from 'react';

interface VirtualStickProps {
  horizontalOnly?: boolean;
  maxRadius?: number;
  onChange: (x: number, y: number) => void;
}

export const VirtualStick: React.FC<VirtualStickProps> = ({
  horizontalOnly = false,
  maxRadius = 56,
  onChange,
}) => {
  const boxRef = useRef<HTMLDivElement>(null);
  const pointerIdRef = useRef<number | null>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0, active: false });

  const updateFromClient = (clientX: number, clientY: number) => {
    const rect = boxRef.current?.getBoundingClientRect();
    if (!rect) return;
    let dx = clientX - (rect.left + rect.width * 0.5);
    let dy = horizontalOnly ? 0 : clientY - (rect.top + rect.height * 0.5);
    const dist = Math.hypot(dx, dy);
    if (dist > maxRadius) {
      dx = (dx / dist) * maxRadius;
      dy = (dy / dist) * maxRadius;
    }
    setKnob({ x: dx, y: dy, active: true });
    onChange(dx / maxRadius, dy / maxRadius);
  };

  const reset = () => {
    pointerIdRef.current = null;
    setKnob({ x: 0, y: 0, active: false });
    onChange(0, 0);
  };

  const sprinting = !horizontalOnly && Math.hypot(knob.x, knob.y) / maxRadius > 0.88;

  return (
    <div
      ref={boxRef}
      onPointerDown={(e) => {
        e.stopPropagation();
        if (pointerIdRef.current !== null) return;
        pointerIdRef.current = e.pointerId;
        e.currentTarget.setPointerCapture(e.pointerId);
        updateFromClient(e.clientX, e.clientY);
      }}
      onPointerMove={(e) => {
        if (e.pointerId !== pointerIdRef.current) return;
        e.stopPropagation();
        updateFromClient(e.clientX, e.clientY);
      }}
      onPointerUp={(e) => {
        if (e.pointerId !== pointerIdRef.current) return;
        e.stopPropagation();
        reset();
      }}
      onPointerCancel={(e) => {
        if (e.pointerId !== pointerIdRef.current) return;
        reset();
      }}
      className="relative flex items-center justify-center rounded-full border border-white/30 bg-[#11161f]/75 select-none touch-none"
      style={{ width: maxRadius * 2 + 34, height: horizontalOnly ? 104 : maxRadius * 2 + 34 }}
      aria-label={horizontalOnly ? 'Steering stick' : 'Movement stick'}
    >
      <div
        className={`h-12 w-12 rounded-full border border-slate-900/50 transition-colors duration-100 ${
          sprinting ? 'bg-amber-500' : knob.active ? 'bg-white' : 'bg-slate-200/80'
        }`}
        style={{
          transform: `translate3d(${knob.x}px, ${knob.y}px, 0)`,
        }}
      />
    </div>
  );
};
