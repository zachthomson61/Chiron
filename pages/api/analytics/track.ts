import type { NextApiRequest, NextApiResponse } from 'next';
import { getAuth } from '@clerk/nextjs/server';
import { prisma } from '@/lib/prisma';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { userId } = getAuth(req);
    const { event, properties } = req.body;

    // Validate required fields
    if (!event) {
      return res.status(400).json({ 
        error: 'Event name is required' 
      });
    }

    // Extract session info from properties
    const { sessionId, stepId, variant, ...otherProperties } = properties || {};

    // Store analytics event
    if (prisma && prisma.analyticsEvent) {
      await prisma.analyticsEvent.create({
        data: {
          userId: userId || 'anonymous',
          event,
          sessionId,
          properties: {
            stepId,
            variant,
            ...otherProperties,
            userAgent: req.headers['user-agent'],
            ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress
          }
        }
      });
    }

    // For specific events, update aggregated metrics
    if (event === 'oqf_step_view' && stepId) {
      // Update funnel metrics
      await updateFunnelMetrics(stepId, variant);
    }

    if (event === 'oqf_complete') {
      // Update completion metrics
      await updateCompletionMetrics(userId, properties);
    }

    if (event === 'oqf_abandon' && stepId) {
      // Update abandonment metrics
      await updateAbandonmentMetrics(stepId, properties);
    }

    res.status(200).json({ 
      success: true,
      message: 'Event tracked successfully'
    });
  } catch (error) {
    console.error('Error tracking event:', error);
    // Don't fail the request even if analytics fails
    res.status(200).json({ 
      success: false,
      message: 'Event tracking failed silently'
    });
  }
}

// Helper function to update funnel metrics
async function updateFunnelMetrics(stepId: string, variant: string) {
  try {
    // Check if we have a funnel metric record for this step
    const existing = await prisma.funnelMetric.findFirst({
      where: {
        stepId,
        variant,
        date: new Date(new Date().setHours(0, 0, 0, 0))
      }
    });

    if (existing) {
      // Increment view count
      await prisma.funnelMetric.update({
        where: { id: existing.id },
        data: {
          views: { increment: 1 }
        }
      });
    } else {
      // Create new metric record
      await prisma.funnelMetric.create({
        data: {
          stepId,
          variant,
          date: new Date(new Date().setHours(0, 0, 0, 0)),
          views: 1,
          completions: 0,
          abandonments: 0
        }
      });
    }
  } catch (error) {
    console.error('Error updating funnel metrics:', error);
  }
}

// Helper function to update completion metrics
async function updateCompletionMetrics(userId: string | null, properties: any) {
  try {
    const { totalSteps, duration } = properties;
    
    // Store completion record
    await prisma.planCompletion.create({
      data: {
        userId: userId || 'anonymous',
        totalSteps: totalSteps || 0,
        duration: duration || 0,
        variant: properties.variant || 'oqf',
        completedAt: new Date()
      }
    });

    // Update daily metrics
    const today = new Date(new Date().setHours(0, 0, 0, 0));
    const existing = await prisma.dailyMetric.findFirst({
      where: {
        date: today,
        variant: properties.variant || 'oqf'
      }
    });

    if (existing) {
      await prisma.dailyMetric.update({
        where: { id: existing.id },
        data: {
          completions: { increment: 1 },
          totalDuration: { increment: duration || 0 }
        }
      });
    } else {
      await prisma.dailyMetric.create({
        data: {
          date: today,
          variant: properties.variant || 'oqf',
          completions: 1,
          abandonments: 0,
          totalDuration: duration || 0
        }
      });
    }
  } catch (error) {
    console.error('Error updating completion metrics:', error);
  }
}

// Helper function to update abandonment metrics
async function updateAbandonmentMetrics(stepId: string, properties: any) {
  try {
    // Update funnel metrics for this step
    const existing = await prisma.funnelMetric.findFirst({
      where: {
        stepId,
        variant: properties.variant || 'oqf',
        date: new Date(new Date().setHours(0, 0, 0, 0))
      }
    });

    if (existing) {
      await prisma.funnelMetric.update({
        where: { id: existing.id },
        data: {
          abandonments: { increment: 1 }
        }
      });
    }

    // Update daily metrics
    const today = new Date(new Date().setHours(0, 0, 0, 0));
    const dailyExisting = await prisma.dailyMetric.findFirst({
      where: {
        date: today,
        variant: properties.variant || 'oqf'
      }
    });

    if (dailyExisting) {
      await prisma.dailyMetric.update({
        where: { id: dailyExisting.id },
        data: {
          abandonments: { increment: 1 }
        }
      });
    }
  } catch (error) {
    console.error('Error updating abandonment metrics:', error);
  }
}





