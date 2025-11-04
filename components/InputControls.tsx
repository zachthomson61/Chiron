import React, { useState, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Check, X } from 'lucide-react';
import type { Answer } from '@/flow/config';

interface BaseInputProps {
  value?: Answer;
  onChange: (value: Answer) => void;
  error?: string;
}

interface Option {
  value: string;
  label: string;
  helper?: string;
}

// Single Choice Radio
export function SingleChoice({ 
  value, 
  onChange, 
  options,
  error 
}: BaseInputProps & { options: Option[] }) {
  return (
    <div className="space-y-3" role="radiogroup" aria-invalid={!!error}>
      {options.map((option) => (
        <label
          key={option.value}
          className={`
            block p-4 rounded-xl border-2 cursor-pointer transition-all
            ${value === option.value
              ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
              : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
            }
          `}
        >
          <div className="flex items-start gap-3">
            <div className="mt-0.5">
              <div className={`
                w-5 h-5 rounded-full border-2 flex items-center justify-center
                ${value === option.value
                  ? 'border-blue-500 bg-blue-500'
                  : 'border-gray-300 dark:border-gray-600'
                }
              `}>
                {value === option.value && (
                  <div className="w-2 h-2 rounded-full bg-white" />
                )}
              </div>
            </div>
            <div className="flex-1">
              <div className="font-medium text-gray-900 dark:text-white">
                {option.label}
              </div>
              {option.helper && (
                <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                  {option.helper}
                </div>
              )}
            </div>
          </div>
          <input
            type="radio"
            name="single-choice"
            value={option.value}
            checked={value === option.value}
            onChange={() => onChange(option.value)}
            className="sr-only"
          />
        </label>
      ))}
    </div>
  );
}

// Multi Choice Checkbox
export function MultiChoice({ 
  value = [], 
  onChange, 
  options,
  error 
}: BaseInputProps & { options: Option[] }) {
  const selected = Array.isArray(value) ? value : [];

  const toggleOption = (optionValue: string) => {
    if (selected.includes(optionValue)) {
      onChange(selected.filter(v => v !== optionValue));
    } else {
      onChange([...selected, optionValue]);
    }
  };

  return (
    <div className="space-y-3" role="group" aria-invalid={!!error}>
      {options.map((option) => (
        <label
          key={option.value}
          className={`
            block p-4 rounded-xl border-2 cursor-pointer transition-all
            ${selected.includes(option.value)
              ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
              : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
            }
          `}
        >
          <div className="flex items-start gap-3">
            <div className="mt-0.5">
              <div className={`
                w-5 h-5 rounded flex items-center justify-center border-2
                ${selected.includes(option.value)
                  ? 'border-blue-500 bg-blue-500'
                  : 'border-gray-300 dark:border-gray-600'
                }
              `}>
                {selected.includes(option.value) && (
                  <Check className="w-3 h-3 text-white" />
                )}
              </div>
            </div>
            <div className="flex-1">
              <div className="font-medium text-gray-900 dark:text-white">
                {option.label}
              </div>
              {option.helper && (
                <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                  {option.helper}
                </div>
              )}
            </div>
          </div>
          <input
            type="checkbox"
            value={option.value}
            checked={selected.includes(option.value)}
            onChange={() => toggleOption(option.value)}
            className="sr-only"
          />
        </label>
      ))}
      {selected.length > 0 && (
        <div className="text-sm text-gray-500 dark:text-gray-400 mt-2">
          {selected.length} selected
        </div>
      )}
    </div>
  );
}

// Number Input
export function NumberInput({ 
  value, 
  onChange, 
  min, 
  max, 
  placeholder,
  error 
}: BaseInputProps & { min?: number; max?: number; placeholder?: string }) {
  return (
    <div className="relative">
      <input
        type="number"
        value={value as number || ''}
        onChange={(e) => {
          const num = parseInt(e.target.value);
          if (!isNaN(num)) {
            onChange(num);
          }
        }}
        min={min}
        max={max}
        placeholder={placeholder}
        className={`
          w-full px-4 py-3 rounded-xl border-2 text-lg
          bg-white dark:bg-gray-800
          text-gray-900 dark:text-white
          placeholder-gray-400 dark:placeholder-gray-500
          focus:outline-none focus:border-blue-500
          transition-colors
          ${error
            ? 'border-red-500'
            : 'border-gray-200 dark:border-gray-700'
          }
        `}
        aria-invalid={!!error}
      />
      {error && (
        <p className="text-red-500 text-sm mt-1">{error}</p>
      )}
    </div>
  );
}

// Range Slider
export function RangeSlider({ 
  value = 50, 
  onChange, 
  min = 0, 
  max = 100, 
  step = 1,
  unit,
  error 
}: BaseInputProps & { min: number; max: number; step?: number; unit?: string }) {
  const numValue = typeof value === 'number' ? value : parseInt(String(value)) || min;
  const percentage = ((numValue - min) / (max - min)) * 100;

  return (
    <div className="space-y-4">
      <div className="relative">
        {/* Track */}
        <div className="h-2 bg-gray-200 dark:bg-gray-700 rounded-full">
          <div 
            className="h-full bg-gradient-to-r from-blue-500 to-purple-500 rounded-full"
            style={{ width: `${percentage}%` }}
          />
        </div>

        {/* Slider */}
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={numValue}
          onChange={(e) => onChange(parseInt(e.target.value))}
          className="absolute inset-0 w-full opacity-0 cursor-pointer"
          aria-invalid={!!error}
        />

        {/* Thumb */}
        <div 
          className="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 pointer-events-none"
          style={{ left: `${percentage}%` }}
        >
          <div className="w-6 h-6 bg-white dark:bg-gray-800 border-2 border-blue-500 rounded-full shadow-md" />
        </div>
      </div>

      {/* Value display */}
      <div className="text-center">
        <span className="text-3xl font-bold text-gray-900 dark:text-white">
          {numValue}
        </span>
        {unit && (
          <span className="text-xl text-gray-500 dark:text-gray-400 ml-1">
            {unit}
          </span>
        )}
      </div>

      {/* Min/Max labels */}
      <div className="flex justify-between text-sm text-gray-500 dark:text-gray-400">
        <span>{min}{unit && ` ${unit}`}</span>
        <span>{max}{unit && ` ${unit}`}</span>
      </div>
    </div>
  );
}

// Chip Select
export function ChipSelect({ 
  value = [], 
  onChange, 
  options,
  error 
}: BaseInputProps & { options: Option[] }) {
  const selected = Array.isArray(value) ? value : [value].filter(Boolean);

  const toggleOption = (optionValue: string) => {
    if (selected.includes(optionValue)) {
      onChange(selected.filter(v => v !== optionValue));
    } else {
      onChange([...selected, optionValue]);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {options.map((option) => (
          <motion.button
            key={option.value}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => toggleOption(option.value)}
            className={`
              px-4 py-2 rounded-full font-medium transition-all
              ${selected.includes(option.value)
                ? 'bg-gradient-to-r from-blue-500 to-purple-500 text-white'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700'
              }
            `}
          >
            {option.label}
          </motion.button>
        ))}
      </div>
      {selected.length > 0 && (
        <div className="text-sm text-gray-500 dark:text-gray-400">
          {selected.length} selected
        </div>
      )}
    </div>
  );
}

// Yes/No Toggle
export function YesNoToggle({ 
  value, 
  onChange,
  error 
}: BaseInputProps) {
  const boolValue = value === true || value === 'true';

  return (
    <div className="flex gap-4 justify-center">
      <motion.button
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        onClick={() => onChange(true)}
        className={`
          px-8 py-4 rounded-xl font-medium text-lg transition-all min-w-[120px]
          ${boolValue
            ? 'bg-green-500 text-white'
            : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700'
          }
        `}
      >
        <Check className="w-5 h-5 inline mr-2" />
        Yes
      </motion.button>

      <motion.button
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        onClick={() => onChange(false)}
        className={`
          px-8 py-4 rounded-xl font-medium text-lg transition-all min-w-[120px]
          ${!boolValue && value !== undefined
            ? 'bg-red-500 text-white'
            : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700'
          }
        `}
      >
        <X className="w-5 h-5 inline mr-2" />
        No
      </motion.button>
    </div>
  );
}

// Time Input
export function TimeInput({ 
  value, 
  onChange,
  error 
}: BaseInputProps) {
  const [hours, setHours] = useState(0);
  const [minutes, setMinutes] = useState(0);

  React.useEffect(() => {
    if (typeof value === 'string') {
      const [h, m] = value.split(':').map(Number);
      setHours(h || 0);
      setMinutes(m || 0);
    }
  }, [value]);

  const updateTime = useCallback((h: number, m: number) => {
    const paddedHours = String(h).padStart(2, '0');
    const paddedMinutes = String(m).padStart(2, '0');
    onChange(`${paddedHours}:${paddedMinutes}`);
  }, [onChange]);

  return (
    <div className="flex items-center gap-4 justify-center">
      <div className="text-center">
        <input
          type="number"
          min={0}
          max={23}
          value={hours}
          onChange={(e) => {
            const h = Math.min(23, Math.max(0, parseInt(e.target.value) || 0));
            setHours(h);
            updateTime(h, minutes);
          }}
          className="w-20 px-3 py-2 text-2xl text-center rounded-lg border-2 border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 focus:outline-none focus:border-blue-500"
        />
        <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">Hours</div>
      </div>

      <div className="text-2xl font-bold text-gray-400">:</div>

      <div className="text-center">
        <input
          type="number"
          min={0}
          max={59}
          value={minutes}
          onChange={(e) => {
            const m = Math.min(59, Math.max(0, parseInt(e.target.value) || 0));
            setMinutes(m);
            updateTime(hours, m);
          }}
          className="w-20 px-3 py-2 text-2xl text-center rounded-lg border-2 border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 focus:outline-none focus:border-blue-500"
        />
        <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">Minutes</div>
      </div>
    </div>
  );
}

// Text Input
export function TextInput({ 
  value, 
  onChange, 
  placeholder,
  multiline = false,
  error 
}: BaseInputProps & { placeholder?: string; multiline?: boolean }) {
  const Component = multiline ? 'textarea' : 'input';

  return (
    <div className="relative">
      <Component
        type={multiline ? undefined : 'text'}
        value={String(value || '')}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className={`
          w-full px-4 py-3 rounded-xl border-2 text-lg
          bg-white dark:bg-gray-800
          text-gray-900 dark:text-white
          placeholder-gray-400 dark:placeholder-gray-500
          focus:outline-none focus:border-blue-500
          transition-colors
          ${multiline ? 'min-h-[120px] resize-y' : ''}
          ${error
            ? 'border-red-500'
            : 'border-gray-200 dark:border-gray-700'
          }
        `}
        aria-invalid={!!error}
      />
      {error && (
        <p className="text-red-500 text-sm mt-1">{error}</p>
      )}
    </div>
  );
}

