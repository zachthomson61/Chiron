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
    
    const { stepId, answer, state, timestamp } = req.body;

    // Validate required fields
    if (!stepId || answer === undefined) {
      return res.status(400).json({ 
        error: 'Missing required fields: stepId and answer are required' 
      });
    }

    // Save to database if user is authenticated
    if (userId) {
      // Check if we have an existing draft
      const existingDraft = await prisma.planDraft.findFirst({
        where: {
          userId,
          status: 'in_progress'
        },
        orderBy: {
          createdAt: 'desc'
        }
      });

      if (existingDraft) {
        // Update existing draft
        await prisma.planDraft.update({
          where: { id: existingDraft.id },
          data: {
            answers: {
              ...((existingDraft.answers as any) || {}),
              [stepId]: answer
            },
            currentStep: stepId,
            state: state || existingDraft.state,
            lastUpdatedAt: new Date(timestamp || Date.now())
          }
        });

        // Log the step completion
        await prisma.planStepLog.create({
          data: {
            draftId: existingDraft.id,
            userId,
            stepId,
            answer: JSON.stringify(answer),
            timestamp: new Date(timestamp || Date.now())
          }
        });
      } else {
        // Create new draft
        const newDraft = await prisma.planDraft.create({
          data: {
            userId,
            answers: { [stepId]: answer },
            currentStep: stepId,
            state: state || {},
            status: 'in_progress',
            lastUpdatedAt: new Date(timestamp || Date.now())
          }
        });

        // Log the first step
        await prisma.planStepLog.create({
          data: {
            draftId: newDraft.id,
            userId,
            stepId,
            answer: JSON.stringify(answer),
            timestamp: new Date(timestamp || Date.now())
          }
        });
      }
    }

    // Return success
    res.status(200).json({ 
      success: true,
      message: 'Answer saved successfully'
    });
  } catch (error) {
    console.error('Error saving answer:', error);
    res.status(500).json({ 
      error: 'Failed to save answer',
      details: process.env.NODE_ENV === 'development' ? error : undefined
    });
  }
}







