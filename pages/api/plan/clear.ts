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
    // Get user from Clerk
    const { userId } = getAuth(req);
    
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Mark all in-progress drafts as abandoned
    await prisma.planDraft.updateMany({
      where: {
        userId,
        status: 'in_progress'
      },
      data: {
        status: 'abandoned',
        abandonedAt: new Date()
      }
    });

    // Log the clear event
    await prisma.analyticsEvent.create({
      data: {
        userId,
        event: 'plan_draft_cleared',
        properties: {
          method: 'manual_clear',
          timestamp: new Date()
        }
      }
    });

    res.status(200).json({ 
      success: true,
      message: 'Draft cleared successfully'
    });
  } catch (error) {
    console.error('Error clearing draft:', error);
    res.status(500).json({ 
      error: 'Failed to clear draft',
      details: process.env.NODE_ENV === 'development' ? error : undefined
    });
  }
}








