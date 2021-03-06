/* $Id: tstInt.cpp $ */
/** @file
 * SUP Testcase - Test the interrupt gate feature of the support library.
 */

/*
 * Copyright (C) 2006-2007 Oracle Corporation
 *
 * This file is part of VirtualBox Open Source Edition (OSE), as
 * available from http://www.virtualbox.org. This file is free software;
 * you can redistribute it and/or modify it under the terms of the GNU
 * General Public License (GPL) as published by the Free Software
 * Foundation, in version 2 as it comes in the "COPYING" file of the
 * VirtualBox OSE distribution. VirtualBox OSE is distributed in the
 * hope that it will be useful, but WITHOUT ANY WARRANTY of any kind.
 *
 * The contents of this file may alternatively be used under the terms
 * of the Common Development and Distribution License Version 1.0
 * (CDDL) only, as it comes in the "COPYING.CDDL" file of the
 * VirtualBox OSE distribution, in which case the provisions of the
 * CDDL are applicable instead of those of the GPL.
 *
 * You may elect to license modified versions of this file under the
 * terms and conditions of either the GPL or the CDDL or both.
 */


/*******************************************************************************
*   Header Files                                                               *
*******************************************************************************/
#include <VBox/sup.h>
#include <VBox/vmm/vm.h>
#include <VBox/vmm/vmm.h>
#include <VBox/err.h>
#include <VBox/param.h>
#include <iprt/asm-amd64-x86.h>
#include <iprt/initterm.h>
#include <iprt/stream.h>
#include <iprt/string.h>
#include <iprt/alloc.h>
#include <iprt/time.h>
#include <iprt/path.h>


int main(int argc, char **argv)
{
    int rcRet = 0;
    int i;
    int rc;
    int cIterations = argc > 1 ? RTStrToUInt32(argv[1]) : 32;
    if (cIterations == 0)
        cIterations = 64;

    /*
     * Init.
     */
    RTR3InitExe(argc, &argv, 0);
    PSUPDRVSESSION pSession;
    rc = SUPR3Init(&pSession);
    rcRet += rc != 0;
    RTPrintf("tstInt: SUPR3Init -> rc=%Rrc\n", rc);
    char szFile[RTPATH_MAX];
    if (!rc)
    {
        rc = RTPathExecDir(szFile, sizeof(szFile) - sizeof("/VMMR0.r0"));
    }
    char szAbsFile[RTPATH_MAX];
    if (RT_SUCCESS(rc))
    {
        strcat(szFile, "/VMMR0.r0");
        rc = RTPathAbs(szFile, szAbsFile, sizeof(szAbsFile));
    }
    if (RT_SUCCESS(rc))
    {
        /*
         * Load VMM code.
         */
        rc = SUPR3LoadVMM(szAbsFile);
        if (RT_SUCCESS(rc))
        {
            /*
             * Create a fake 'VM'.
             */
            PVMR0 pVMR0 = NIL_RTR0PTR;
            PVM pVM = NULL;
            const unsigned cPages = RT_ALIGN_Z(sizeof(*pVM), PAGE_SIZE) >> PAGE_SHIFT;
            PSUPPAGE paPages = (PSUPPAGE)RTMemAllocZ(cPages * sizeof(SUPPAGE));
            if (paPages)
                rc = SUPR3LowAlloc(cPages, (void **)&pVM, &pVMR0, &paPages[0]);
            else
                rc = VERR_NO_MEMORY;
            if (RT_SUCCESS(rc))
            {
                pVM->pVMRC = 0;
                pVM->pVMR3 = pVM;
                pVM->pVMR0 = pVMR0;
                pVM->paVMPagesR3 = paPages;
                pVM->pSession = pSession;
                pVM->enmVMState = VMSTATE_CREATED;

                rc = SUPR3SetVMForFastIOCtl(pVMR0);
                if (!rc)
                {

                    /*
                     * Call VMM code with invalid function.
                     */
                    for (i = cIterations; i > 0; i--)
                    {
                        rc = SUPR3CallVMMR0(pVMR0, NIL_VMCPUID, VMMR0_DO_SLOW_NOP, NULL);
                        if (rc != VINF_SUCCESS)
                        {
                            RTPrintf("tstInt: SUPR3CallVMMR0 -> rc=%Rrc i=%d Expected VINF_SUCCESS!\n", rc, i);
                            rcRet++;
                            break;
                        }
                    }
                    RTPrintf("tstInt: Performed SUPR3CallVMMR0 %d times (rc=%Rrc)\n", cIterations, rc);

                    /*
                     * The fast path.
                     */
                    if (rc == VINF_SUCCESS)
                    {
                        RTTimeNanoTS();
                        uint64_t StartTS = RTTimeNanoTS();
                        uint64_t StartTick = ASMReadTSC();
                        uint64_t MinTicks = UINT64_MAX;
                        for (i = 0; i < 1000000; i++)
                        {
                            uint64_t OneStartTick = ASMReadTSC();
                            rc = SUPR3CallVMMR0Fast(pVMR0, VMMR0_DO_NOP, 0);
                            uint64_t Ticks = ASMReadTSC() - OneStartTick;
                            if (Ticks < MinTicks)
                                MinTicks = Ticks;

                            if (RT_UNLIKELY(rc != VINF_SUCCESS))
                            {
                                RTPrintf("tstInt: SUPR3CallVMMR0Fast -> rc=%Rrc i=%d Expected VINF_SUCCESS!\n", rc, i);
                                rcRet++;
                                break;
                            }
                        }
                        uint64_t Ticks = ASMReadTSC() - StartTick;
                        uint64_t NanoSecs = RTTimeNanoTS() - StartTS;

                        RTPrintf("tstInt: SUPR3CallVMMR0Fast - %d iterations in %llu ns / %llu ticks. %llu ns / %#llu ticks per iteration. Min %llu ticks.\n",
                                 i, NanoSecs, Ticks, NanoSecs / i, Ticks / i, MinTicks);

                        /*
                         * The ordinary path.
                         */
                        RTTimeNanoTS();
                        StartTS = RTTimeNanoTS();
                        StartTick = ASMReadTSC();
                        MinTicks = UINT64_MAX;
                        for (i = 0; i < 1000000; i++)
                        {
                            uint64_t OneStartTick = ASMReadTSC();
                            rc = SUPR3CallVMMR0Ex(pVMR0, NIL_VMCPUID, VMMR0_DO_SLOW_NOP, 0, NULL);
                            uint64_t OneTicks = ASMReadTSC() - OneStartTick;
                            if (OneTicks < MinTicks)
                                MinTicks = OneTicks;

                            if (RT_UNLIKELY(rc != VINF_SUCCESS))
                            {
                                RTPrintf("tstInt: SUPR3CallVMMR0Ex -> rc=%Rrc i=%d Expected VINF_SUCCESS!\n", rc, i);
                                rcRet++;
                                break;
                            }
                        }
                        Ticks = ASMReadTSC() - StartTick;
                        NanoSecs = RTTimeNanoTS() - StartTS;

                        RTPrintf("tstInt: SUPR3CallVMMR0Ex   - %d iterations in %llu ns / %llu ticks. %llu ns / %#llu ticks per iteration. Min %llu ticks.\n",
                                 i, NanoSecs, Ticks, NanoSecs / i, Ticks / i, MinTicks);
                    }
                }
                else
                {
                    RTPrintf("tstInt: SUPR3SetVMForFastIOCtl failed: %Rrc\n", rc);
                    rcRet++;
                }
            }
            else
            {
                RTPrintf("tstInt: SUPR3ContAlloc(%#zx,,) failed\n", sizeof(*pVM));
                rcRet++;
            }

            /*
             * Unload VMM.
             */
            rc = SUPR3UnloadVMM();
            if (rc)
            {
                RTPrintf("tstInt: SUPR3UnloadVMM failed with rc=%Rrc\n", rc);
                rcRet++;
            }
        }
        else
        {
            RTPrintf("tstInt: SUPR3LoadVMM failed with rc=%Rrc\n", rc);
            rcRet++;
        }

        /*
         * Terminate.
         */
        rc = SUPR3Term(false /*fForced*/);
        rcRet += rc != 0;
        RTPrintf("tstInt: SUPR3Term -> rc=%Rrc\n", rc);
    }

    return !!rc;
}

