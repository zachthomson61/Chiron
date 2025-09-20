import type { MicrocycleTemplate } from './types';

export const TEMPLATES: MicrocycleTemplate[] = [
  { split: 'FB-3', days: [
    { dayIndex: 1, slotPlan: [{ muscles:['full_body'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 3, slotPlan: [{ muscles:['full_body'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 5, slotPlan: [{ muscles:['full_body'], slots: 6, minutesBudget: 60 }]},
  ]},
  { split: 'UL-4', days: [
    { dayIndex: 1, slotPlan: [{ muscles:['upper'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 2, slotPlan: [{ muscles:['lower'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 4, slotPlan: [{ muscles:['upper'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 5, slotPlan: [{ muscles:['lower'], slots: 6, minutesBudget: 60 }]},
  ]},
  { split: 'PPL-6', days: [
    { dayIndex: 1, slotPlan: [{ muscles:['push'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 2, slotPlan: [{ muscles:['pull'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 3, slotPlan: [{ muscles:['legs'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 4, slotPlan: [{ muscles:['push'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 5, slotPlan: [{ muscles:['pull'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 6, slotPlan: [{ muscles:['legs'], slots: 6, minutesBudget: 60 }]},
  ]},
  { split: 'ULUL-4', days: [
    { dayIndex: 1, slotPlan: [{ muscles:['upper'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 2, slotPlan: [{ muscles:['lower'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 4, slotPlan: [{ muscles:['upper'], slots: 6, minutesBudget: 60 }]},
    { dayIndex: 5, slotPlan: [{ muscles:['lower'], slots: 6, minutesBudget: 60 }]},
  ]},
];




