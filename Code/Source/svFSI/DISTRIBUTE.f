!
! Copyright (c) Stanford University, The Regents of the University of
!               California, and others.
!
! All Rights Reserved.
!
! See Copyright-SimVascular.txt for additional details.
!
! Permission is hereby granted, free of charge, to any person obtaining
! a copy of this software and associated documentation files (the
! "Software"), to deal in the Software without restriction, including
! without limitation the rights to use, copy, modify, merge, publish,
! distribute, sublicense, and/or sell copies of the Software, and to
! permit persons to whom the Software is furnished to do so, subject
! to the following conditions:
!
! The above copyright notice and this permission notice shall be included
! in all copies or substantial portions of the Software.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
! IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
! TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
! PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
! OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
! EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
! PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
! PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
! LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
! NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
! SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
!
!--------------------------------------------------------------------
!
!     This routine partitions the mesh, distributes values from
!     single processor to multiple processors and prepares the problem
!     to be lunched with several processors.
!
!--------------------------------------------------------------------

      SUBROUTINE DISTRIBUTE
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      LOGICAL :: flag
      INTEGER :: iEq, iM, iFa, a, e, i, Ac

      INTEGER, ALLOCATABLE :: part(:), gmtl(:)
      REAL, ALLOCATABLE :: iWgt(:)
      REAL(KIND=8), ALLOCATABLE :: wgt(:,:), wrk(:), tmpX(:,:),
     2   tmpX3(:,:,:)
      TYPE(mshType), ALLOCATABLE :: tMs(:)

!     Preparing IO incase of error or warning. I'm keeping dbg channel
!     closed is slave processors. Warning is closed only if it is
!     closed in master
      IF (.NOT.resetSim) THEN
         CALL cm%bcast(pClr)
         CALL cm%bcast(appPath)
         CALL cm%bcast(wrn%oTS)
         wrn%oTF = wrn%oTS

!     Constructing data structures one by one
         CALL cm%bcast(nMsh)
         CALL cm%bcast(nsd)
         CALL cm%bcast(rmsh%isReqd)
      END IF
      CALL cm%bcast(gtnNo)

      IF (cm%slv()) ALLOCATE(msh(nMsh))

!     tMs is a temporary variable to keep fa%gN of the old meshes.
!     wgt and wrk are the assigned portion of each mesh to the each
!     processor.
      ALLOCATE(tMs(nMsh), wgt(nMsh,cm%np()), wrk(nMsh), iWgt(cm%np()),
     2   gmtl(gtnNo))

!     Here is rough estimation of how each mesh should be splited
!     between processors
      wrk = REAL(msh%gnNo,8)/REAL(gtnNo,8)
      CALL cm%bcast(wrk)
      CALL SPLITJOBS(nMsh, cm%np(), wgt, wrk)

!     First partitioning the meshes
!     gmtl:  gtnNo --> tnNo
      tnNo = 0
      gmtl = 0
      IF (cm%seq()) THEN
         tnNo = gtnNo
         ALLOCATE(ltg(tnNo))
         DO a=1, tnNo
            ltg(a) = a
         END DO
      END IF
      DO iM=1, nMsh
         dbg = "Partitioning mesh "//iM
         iWgt = REAL(wgt(iM,:)/SUM(wgt(iM,:)))
         CALL PARTMSH(msh(iM), gmtl, cm%np(), iWgt)
      END DO

!     Setting gtl pointer in case that it is needed and mapping IEN
      DO iM=1, nMsh
         IF (ALLOCATED(msh(iM)%lN)) DEALLOCATE(msh(iM)%lN)
         ALLOCATE(msh(iM)%lN(tnNo))
         msh(iM)%lN = 0
         DO a=1, msh(iM)%nNo
            Ac             = msh(iM)%gN(a)
            msh(iM)%lN(Ac) = a
         END DO
         DO e=1, msh(iM)%nEl
            DO a=1, msh(iM)%eNoN
               Ac               = msh(iM)%IEN(a,e)
               msh(iM)%IEN(a,e) = msh(iM)%gN(Ac)
            END DO
         END DO
      END DO
      IF (cm%seq()) THEN
!        Rearrange body force structure, if necessary
         DO iM=1, nMsh
            IF (ALLOCATED(msh(iM)%bf)) THEN
               ALLOCATE(tmpX3(msh(iM)%bf%dof,gtnNo,msh(iM)%bf%nTP))
               tmpX3 = msh(iM)%bf%d
               DEALLOCATE(msh(iM)%bf%d)
               ALLOCATE(msh(iM)%bf%d(msh(iM)%bf%dof,msh(iM)%nNo,
     2            msh(iM)%bf%nTP))
               msh(iM)%bf%d = 0D0
               DO i=1, msh(iM)%bf%nTP
                  DO a=1, msh(iM)%nNo
                     Ac = msh(iM)%gN(a)
                     msh(iM)%bf%d(:,a,i) = tmpX3(:,Ac,i)
                  END DO
               END DO
               DEALLOCATE(tmpX3)
            END IF
         END DO
         RETURN
      END IF

!     Partitioning the faces
      DO iM=1, nMsh
         ALLOCATE(tMs(iM)%fa(msh(iM)%nFa))
         DO iFa=1, msh(iM)%nFa
            CALL PARTFACE(msh(iM), msh(iM)%fa(iFa), tMs(iM)%fa(iFa),
     2         gmtl)
         END DO
      END DO

!     Sending data from read by master in READFILES to slaves
      IF (.NOT.resetSim) THEN
         CALL cm%bcast(nstd)
         CALL cm%bcast(stopTrigName)
         CALL cm%bcast(iniFilePath)
         CALL cm%bcast(stFileName)
         CALL cm%bcast(stFileFlag)
         CALL cm%bcast(stFileIncr)
         CALL cm%bcast(stFileRepl)
         CALL cm%bcast(saveIncr)
         CALL cm%bcast(saveATS)
         CALL cm%bcast(saveAve)
         CALL cm%bcast(mvMsh)
         CALL cm%bcast(nITS)
         CALL cm%bcast(nTS)
         CALL cm%bcast(nEq)
         CALL cm%bcast(dt)
         CALL cm%bcast(useTrilinosLS)
         CALL cm%bcast(useTrilinosAssemAndLS)
         CALL cm%bcast(zeroAve)
         CALL cm%bcast(ustRd)
         IF (rmsh%isReqd) THEN
            CALL cm%bcast(rmsh%method)
            CALL cm%bcast(rmsh%freq)
            CALL cm%bcast(rmsh%cpVar)
            IF (cm%slv()) THEN
               ALLOCATE(rmsh%maxEdgeSize(nMsh))
               rmsh%minDihedAng = 0D0
               rmsh%maxRadRatio = 0D0
            END IF
            call cm%bcast(rmsh%maxEdgeSize)
         END IF
         CALL cm%bcast(iCntct)
         IF (iCntct) THEN
            CALL cm%bcast(cntctM%cType)
            CALL cm%bcast(cntctM%k)
            CALL cm%bcast(cntctM%c)
            CALL cm%bcast(cntctM%h)
            CALL cm%bcast(cntctM%al)
         END IF
         CALL cm%bcast(ibFlag)
         IF (ibFlag) CALL DISTIB()
      END IF

!     Distributing X to processors
      IF (cm%mas()) THEN
         ALLOCATE(tmpX(nsd,gtnNo))
         tmpX = x
         DEALLOCATE(x)
      ELSE
         ALLOCATE(tmpX(0,0))
      END IF
      ALLOCATE(x(nsd,tnNo))
      x = LOCAL(tmpX)
      DEALLOCATE(tmpX)

!     Distributing lM%dmnId if present to processors
      flag = ALLOCATED(dmnId)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%mas()) THEN
            ALLOCATE(part(gtnNo))
            part = dmnId
            DEALLOCATE(dmnId)
         ELSE
            ALLOCATE(part(0))
         END IF
         ALLOCATE(dmnId(tnNo))
         dmnId = LOCAL(part)
         DEALLOCATE(part)
      END IF

!     Distribute fiber orientation (fN) to processors
      CALL cm%bcast(nFn)
      flag = ALLOCATED(fN)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%mas()) THEN
            ALLOCATE(tmpX(nFn*nsd,gtnNo))
            tmpX = fN
            DEALLOCATE(fN)
         ELSE
            ALLOCATE(tmpX(0,0))
         END IF
         ALLOCATE(fN(nFn*nsd,tnNo))
         fN = LOCAL(tmpX)
         DEALLOCATE(tmpX)
      END IF

!     Distribute prestress (pS0) to processors
      flag = ALLOCATED(pS0)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%mas()) THEN
            ALLOCATE(tmpX(nstd,gtnNo))
            tmpX = pS0
            DEALLOCATE(pS0)
         ELSE
            ALLOCATE(tmpX(0,0))
         END IF
         ALLOCATE(pS0(nstd,tnNo))
         pS0 = LOCAL(tmpX)
         DEALLOCATE(tmpX)
      END IF

!     Distribute body force to processors
      DO iM=1, nMsh
         flag = ALLOCATED(msh(iM)%bf)
         CALL cm%bcast(flag)
         IF (flag) THEN
            IF (cm%slv()) ALLOCATE(msh(iM)%bf)
            CALL cm%bcast(msh(iM)%bf%dof)
            CALL cm%bcast(msh(iM)%bf%nTP)
            CALL cm%bcast(msh(iM)%bf%period)
            IF (cm%slv()) ALLOCATE(msh(iM)%bf%t(msh(iM)%bf%nTP))
            CALL cm%bcast(msh(iM)%bf%t)

            IF (cm%mas()) THEN
               ALLOCATE(tmpX3(msh(iM)%bf%dof,gtnNo,msh(iM)%bf%nTP))
               tmpX3 = msh(iM)%bf%d
               DEALLOCATE(msh(iM)%bf%d)
            ELSE
               ALLOCATE(tmpX3(0,0,0))
            END IF
            ALLOCATE(tmpX(msh(iM)%bf%dof,tnNo),
     2         msh(iM)%bf%d(msh(iM)%bf%dof,msh(iM)%nNo,msh(iM)%bf%nTP))
            msh(iM)%bf%d = 0D0
            DO i=1, msh(iM)%bf%nTP
               tmpX = LOCAL(tmpX3(:,:,i))
               DO a=1, msh(iM)%nNo
                  Ac = msh(iM)%gN(a)
                  msh(iM)%bf%d(:,a,i) = tmpX(:,Ac)
               END DO
            END DO
            DEALLOCATE(tmpX3, tmpX)
         END IF
      END DO

!     And distributing eq to processors
      IF (cm%slv()) ALLOCATE(eq(nEq))
      DO iEq=1, nEq
         CALL DISTEQ(eq(iEq), tMs, gmtl)
         dbg = "Distributed equation "//iEq
      END DO

!     Communicating cplBC data
      CALL cm%bcast(cplBC%nFa)
      CALL cm%bcast(cplBC%nX)
      IF (.NOT. cm%mas() .AND. .NOT.ALLOCATED(cplBC%xo))
     2   ALLOCATE(cplBC%xo(cplBC%nX))
      IF (cplBC%nX .NE. 0) CALL cm%bcast(cplBC%xo)

      DO iM=1, nMsh
         CALL DESTROY(tMs(iM))
      END DO
      DEALLOCATE(tMs)

      RETURN
      END SUBROUTINE DISTRIBUTE
!####################################################################
!     This routine distributes immersed boundary data structures
      SUBROUTINE DISTIB()
      USE COMMOD
      IMPLICIT NONE

      INTEGER iM, iFa
      LOGICAL flag

      IF (cm%slv()) ALLOCATE(ib)

      CALL cm%bcast(ib%mthd)
      CALL cm%bcast(ib%fcFlag)
      CALL cm%bcast(ib%fbFlag)

      CALL cm%bcast(ib%nMsh)
      CALL cm%bcast(ib%tnNo)
      IF (cm%slv()) THEN
         ALLOCATE(ib%msh(ib%nMsh))
         ALLOCATE(ib%x(nsd,ib%tnNo))
      END IF
      CALL cm%bcast(ib%x)

      DO iM=1, ib%nMsh
         CALL DISTIBMSH(ib%msh(iM))
         DO iFa=1, ib%msh(iM)%nFa
            CALL DISTIBFa(ib%msh(iM), ib%msh(iM)%fa(iFa))
         END DO
      END DO

      CALL cm%bcast(ib%nFn)
      flag = ALLOCATED(ib%fN)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(ib%fN(ib%nFn*nsd,ib%tnNo))
         CALL cm%bcast(ib%fN)
      END IF

      RETURN
      END SUBROUTINE DISTIB
!--------------------------------------------------------------------
      SUBROUTINE DISTIBMSH(lM)
      USE COMMOD
      IMPLICIT NONE

      TYPE(mshType), INTENT(INOUT) :: lM

      INTEGER i, insd

      CALL cm%bcast(lM%lShpF)
      CALL cm%bcast(lM%lShl)
      CALL cm%bcast(lM%eType)
      CALL cm%bcast(lM%eNoN)
      CALL cm%bcast(lM%gnEl)
      CALL cm%bcast(lM%gnNo)
      CALL cm%bcast(lM%nFa)
      CALL cm%bcast(lM%nG)
      CALL cm%bcast(lM%name)
      CALL cm%bcast(lM%dx)

      IF (cm%slv()) THEN
         lM%nNo = lM%gnNo
         lM%nEl = lM%gnEl
         ALLOCATE(lM%gN(lM%nNo))
         ALLOCATE(lM%lN(ib%tnNo))
         ALLOCATE(lM%IEN(lM%eNoN, lM%nEl))
         ALLOCATE(lM%eId(lM%nEl))
         ALLOCATE(lM%fa(lM%nFa))
         CALL SELECTELE(lM)
      END IF
      CALL cm%bcast(lM%gN)
      CALL cm%bcast(lM%lN)
      CALL cm%bcast(lM%IEN)
      CALL cm%bcast(lM%eId)

      IF (lM%eType .EQ. eType_NRB) THEN
         CALL cm%bcast(lM%nSl)
         insd = nsd
         IF (lM%lShl) insd = nsd - 1
         IF (cm%slv()) THEN
            ALLOCATE(lM%nW(lM%gnNo))
            ALLOCATE(lM%INN(insd,lM%gnEl))
            ALLOCATE(lM%bs(insd))
         END IF
         CALL cm%bcast(lM%nW)
         CALL cm%bcast(lM%INN)
         DO i=1, insd
            CALL cm%bcast(lM%bs(i)%n)
            CALL cm%bcast(lM%bs(i)%nG)
            CALL cm%bcast(lM%bs(i)%nEl)
            CALL cm%bcast(lM%bs(i)%nSl)
            CALL cm%bcast(lM%bs(i)%p)
            IF (cm%slv()) ALLOCATE(lM%bs(i)%xi(lM%bs(i)%n))
            CALL cm%bcast(lM%bs(i)%xi)
            lM%bs(i)%nNo = lM%bs(i)%n - lM%bs(i)%p - 1
         END DO
      END IF

      RETURN
      END SUBROUTINE DISTIBMSH
!--------------------------------------------------------------------
      SUBROUTINE DISTIBFa(lM, lFa)
      USE COMMOD
      IMPLICIT NONE

      TYPE(mshType), INTENT(INOUT) :: lM
      TYPE(faceType), INTENT(INOUT) :: lFa

      CALL cm%bcast(lFa%d)
      CALL cm%bcast(lFa%eNoN)
      CALL cm%bcast(lFa%nEl)
      CALL cm%bcast(lFa%nNo)
      CALL cm%bcast(lFa%name)
      IF (cm%slv()) THEN
         ALLOCATE(lFa%IEN(lFa%eNoN,lFa%nEl))
         ALLOCATE(lFa%gN(lFa%nNo))
         ALLOCATE(lFa%lN(ib%tnNo))
         ALLOCATE(lFa%gE(lFa%nEl))
         CALL SELECTELEB(lM, lFa)
      END IF
      CALL cm%bcast(lFa%IEN)
      CALL cm%bcast(lFa%gN)
      CALL cm%bcast(lFa%lN)
      CALL cm%bcast(lFa%gE)

      RETURN
      END SUBROUTINE DISTIBFa
!####################################################################
!     This routine distributes equations between processors
      SUBROUTINE DISTEQ(lEq, tMs, gmtl)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      INTEGER, INTENT(IN) :: gmtl(gtnNo)
      TYPE(eqType), INTENT(INOUT) :: lEq
      TYPE(mshType), INTENT(IN) :: tMs(nMsh)

      LOGICAL flag
      INTEGER iDmn, iOut, iBc

!     Distribute equation parameters
      CALL cm%bcast(lEq%nOutput)
      CALL cm%bcast(lEq%coupled)
      CALL cm%bcast(lEq%maxItr)
      CALL cm%bcast(lEq%minItr)
      CALL cm%bcast(lEq%roInf)
      CALL cm%bcast(lEq%phys)
      CALL cm%bcast(lEq%nDmn)
      CALL cm%bcast(lEq%nBc)
      CALL cm%bcast(lEq%tol)
      CALL cm%bcast(lEq%dBr)
      IF (ibFlag) THEN
         CALL cm%bcast(lEq%nDmnIB)
         CALL cm%bcast(lEq%nBcIB)
      END IF

!     Distribute linear solver settings
      CALL cm%bcast(lEq%FSILS%foC)
      CALL cm%bcast(lEq%FSILS%LS_type)
      CALL cm%bcast(lEq%FSILS%RI%relTol)
      CALL cm%bcast(lEq%FSILS%GM%relTol)
      CALL cm%bcast(lEq%FSILS%CG%relTol)
      CALL cm%bcast(lEq%FSILS%RI%absTol)
      CALL cm%bcast(lEq%FSILS%GM%absTol)
      CALL cm%bcast(lEq%FSILS%CG%absTol)
      CALL cm%bcast(lEq%FSILS%RI%mItr)
      CALL cm%bcast(lEq%FSILS%GM%mItr)
      CALL cm%bcast(lEq%FSILS%CG%mItr)
      CALL cm%bcast(lEq%FSILS%RI%sD)
      CALL cm%bcast(lEq%FSILS%GM%sD)
      CALL cm%bcast(lEq%FSILS%CG%sD)

      CALL cm%bcast(lEq%ls%LS_Type)
      CALL cm%bcast(lEq%ls%PREC_Type)
      CALL cm%bcast(lEq%ls%relTol)
      CALL cm%bcast(lEq%ls%absTol)
      CALL cm%bcast(lEq%ls%mItr)
      CALL cm%bcast(lEq%ls%sD)
      CALL cm%bcast(lEq%ls%optionsFile%fname)

!     Distribute domain properties
      IF (cm%slv()) ALLOCATE(lEq%dmn(lEq%nDmn))
      DO iDmn=1, lEq%nDmn
         CALL cm%bcast(lEq%dmn(iDmn)%phys)
         CALL cm%bcast(lEq%dmn(iDmn)%Id)
         CALL cm%bcast(lEq%dmn(iDmn)%prop)
         IF (lEq%dmn(iDmn)%phys .EQ. phys_CEP) THEN
            CALL cm%bcast(lEq%dmn(iDmn)%cep%cepType)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%nX)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Diso)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Dani)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Istim%Ts)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Istim%Td)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Istim%Tp)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%Istim%A)
            CALL cm%bcast(lEq%dmn(iDmn)%cep%odes%tIntType)
            IF (lEq%dmn(iDmn)%cep%odes%tIntType .EQ. tIntType_CN2) THEN
               CALL cm%bcast(lEq%dmn(iDmn)%cep%odes%maxItr)
               CALL cm%bcast(lEq%dmn(iDmn)%cep%odes%absTol)
               CALL cm%bcast(lEq%dmn(iDmn)%cep%odes%relTol)
            END IF
         END IF

         IF (lEq%dmn(iDmn)%phys .EQ. phys_struct  .OR.
     2       lEq%dmn(iDmn)%phys .EQ. phys_ustruct .OR.
     3       lEq%dmn(iDmn)%phys .EQ. phys_preSt) THEN
            CALL DIST_MATCONSTS(lEq%dmn(iDmn)%stM)
         END IF
      END DO

      IF (ibFlag) THEN
         IF (cm%slv()) ALLOCATE(lEq%dmnIB(lEq%nDmnIB))
         DO iDmn=1, lEq%nDmnIB
            CALL cm%bcast(lEq%dmnIB(iDmn)%phys)
            CALL cm%bcast(lEq%dmnIB(iDmn)%Id)
            CALL cm%bcast(lEq%dmnIB(iDmn)%prop)
            CALL DIST_MATCONSTS(lEq%dmnIB(iDmn)%stM)
            flag = ALLOCATED(lEq%dmnIB(iDmn)%shlFp)
            CALL cm%bcast(flag)
            IF (flag) THEN
               IF (cm%slv()) ALLOCATE(lEq%dmnIB(iDmn)%shlFp)
               CALL DISTSFP(lEq%dmnIB(iDmn)%shlFp)
            END IF
         END DO
      END IF

!     Distribute output parameters
      IF (cm%slv()) ALLOCATE(lEq%output(lEq%nOutput))
      DO iOut=1, lEq%nOutput
         CALL cm%bcast(lEq%output(iOut)%wtn)
         CALL cm%bcast(lEq%output(iOut)%grp)
         CALL cm%bcast(lEq%output(iOut)%o)
         CALL cm%bcast(lEq%output(iOut)%l)
         CALL cm%bcast(lEq%output(iOut)%name)
      END DO

!     Distribute BC information
      IF (cm%slv()) ALLOCATE(lEq%bc(lEq%nBc))
      DO iBc=1, lEq%nBc
         CALL DISTBC(lEq%bc(iBc), tMs, gmtl)
      END DO

      IF (ibFlag) THEN
         IF (cm%slv()) ALLOCATE(lEq%bcIB(lEq%nBcIB))
         DO iBc=1, lEq%nBcIB
            CALL DISTBCIB(lEq%bcIB(iBc))
         END DO
      END IF

      RETURN
      END SUBROUTINE DISTEQ
!--------------------------------------------------------------------
!     This routine distributes the BCs between processors
      SUBROUTINE DISTBC(lBc, tMs, gmtl)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      INTEGER, INTENT(IN) :: gmtl(gtnNo)
      TYPE(bcType), INTENT(INOUT) :: lBc
      TYPE(mshType), INTENT(IN) :: tMs(nMsh)

      LOGICAL flag
      INTEGER i, j, iDof, nTp, nNo, a, b, Ac

      REAL(KIND=8), ALLOCATABLE :: tmp(:)

      CALL cm%bcast(lBc%cplBCptr)
      CALL cm%bcast(lBc%bType)
      IF (cm%slv()) ALLOCATE(lBc%eDrn(nsd), lBc%h(nsd))
      CALL cm%bcast(lBc%eDrn)
      CALL cm%bcast(lBc%iFa)
      CALL cm%bcast(lBc%iM)
      CALL cm%bcast(lBc%r)
      CALL cm%bcast(lBc%g)
      CALL cm%bcast(lBc%h)
      CALL cm%bcast(lBc%weakDir)
      CALL cm%bcast(lBc%tauB)

!     Communicating time-depandant BC data
      flag = ALLOCATED(lBc%gt)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(lBc%gt)
         CALL cm%bcast(lBc%gt%qi)
         CALL cm%bcast(lBc%gt%qs)
         CALL cm%bcast(lBc%gt%ti)
         CALL cm%bcast(lBc%gt%n)
         CALL cm%bcast(lBc%gt%T)
         j = lBc%gt%n
         IF (cm%slv()) THEN
            ALLOCATE(lBc%gt%r(j))
            ALLOCATE(lBc%gt%i(j))
         END IF
         CALL cm%bcast(lBc%gt%r)
         CALL cm%bcast(lBc%gt%i)
      END IF

!     Communicating moving BC data
      flag = ALLOCATED(lBc%gm)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(lBc%gm)
         CALL cm%bcast(lBc%gm%period)
!     Communication the %t data
         CALL cm%bcast(lBc%gm%nTP)
         CALL cm%bcast(lBc%gm%dof)
         nTp  = lBc%gm%nTP
         iDof = lBc%gm%dof
         IF (cm%slv()) ALLOCATE(lBc%gm%t(nTp))
         CALL cm%bcast(lBc%gm%t)

         nNo  = tMs(lBc%iM)%fa(lBc%iFa)%nNo
         a    = nTp*iDof*nNo
!     Allocating the container and copying the nodes which belong to
!     this processor
         ALLOCATE(tmp(a))
         IF (cm%mas()) THEN
            tmp = RESHAPE(lBc%gm%d,(/a/))
            DEALLOCATE(lBc%gm%d)
         END IF

         CALL cm%bcast(tmp)
!     This is the new number of nodes
         a = msh(lBc%iM)%fa(lBc%iFa)%nNo
         ALLOCATE(lBc%gm%d(iDof,a,nTp))
         b = 0
         DO a=1, nNo
            Ac = tMs(lBc%iM)%fa(lBc%iFa)%gN(a)
            Ac = gmtl(Ac)
            IF (Ac .NE. 0) THEN
               b = b + 1
               DO i=1, nTP
                  j = iDof*((i-1)*nNo + a - 1)
                  lBc%gm%d(:,b,i) = tmp(j+1:j+iDof)
               END DO
            END IF
         END DO
      END IF

!     Communicating profile data
      flag = ALLOCATED(lBc%gx)
      CALL cm%bcast(flag)
      IF (flag) THEN
         nNo = tMs(lBc%iM)%fa(lBc%iFa)%nNo
         IF (ALLOCATED(tmp)) DEALLOCATE(tmp)
         ALLOCATE(tmp(nNo))
         IF (cm%mas()) THEN
            tmp = lBc%gx
            DEALLOCATE(lBc%gx)
         END IF
         CALL cm%bcast(tmp)
!     This is the new number of nodes
         a = msh(lBc%iM)%fa(lBc%iFa)%nNo
         ALLOCATE(lBc%gx(a))
         b = 0
         DO a=1, nNo
            Ac = tMs(lBc%iM)%fa(lBc%iFa)%gN(a)
            Ac = gmtl(Ac)
            IF (Ac .NE. 0) THEN
               b = b + 1
               lBc%gx(b) = tmp(a)
            END IF
         END DO
      END IF

      RETURN
      END SUBROUTINE DISTBC
!--------------------------------------------------------------------
!     This routine distributes the BCs on immersed surfaces
      SUBROUTINE DISTBCIB(lBc)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      TYPE(bcType), INTENT(INOUT) :: lBc

      LOGICAL flag
      INTEGER i, j, iDof, nTp, nNo, a

      REAL(KIND=8), ALLOCATABLE :: tmp(:)

      CALL cm%bcast(lBc%bType)
      IF (cm%slv()) ALLOCATE(lBc%eDrn(nsd))
      CALL cm%bcast(lBc%eDrn)
      CALL cm%bcast(lBc%iFa)
      CALL cm%bcast(lBc%iM)
      CALL cm%bcast(lBc%r)
      CALL cm%bcast(lBc%g)
      CALL cm%bcast(lBc%weakDir)
      CALL cm%bcast(lBc%tauB)
      CALL cm%bcast(lBc%tauF)
      CALL cm%bcast(lBc%fbN)

!     Communicating time-depandant BC data
      flag = ALLOCATED(lBc%gt)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(lBc%gt)
         CALL cm%bcast(lBc%gt%qi)
         CALL cm%bcast(lBc%gt%qs)
         CALL cm%bcast(lBc%gt%ti)
         CALL cm%bcast(lBc%gt%n)
         CALL cm%bcast(lBc%gt%T)
         j = lBc%gt%n
         IF (cm%slv()) THEN
            ALLOCATE(lBc%gt%r(j))
            ALLOCATE(lBc%gt%i(j))
         END IF
         CALL cm%bcast(lBc%gt%r)
         CALL cm%bcast(lBc%gt%i)
      END IF

!     Communicating moving BC data
      flag = ALLOCATED(lBc%gm)
      CALL cm%bcast(flag)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(lBc%gm)
         CALL cm%bcast(lBc%gm%period)
!     Communication the %t data
         CALL cm%bcast(lBc%gm%nTP)
         CALL cm%bcast(lBc%gm%dof)
         nTp  = lBc%gm%nTP
         iDof = lBc%gm%dof
         IF (cm%slv()) ALLOCATE(lBc%gm%t(nTp))
         CALL cm%bcast(lBc%gm%t)

         nNo  = ib%msh(lBc%iM)%fa(lBc%iFa)%nNo
         a    = nTp*iDof*nNo
!     Allocating the container and copying the nodes which belong to
!     this processor
         ALLOCATE(tmp(a))
         IF (cm%mas()) THEN
            tmp = RESHAPE(lBc%gm%d,(/a/))
            DEALLOCATE(lBc%gm%d)
         ELSE
            ALLOCATE(lBc%gm%d(iDof,nNo,nTp))
         END IF

         CALL cm%bcast(tmp)
         DO a=1, nNo
            DO i=1, nTP
               j = iDof*((i-1)*nNo + a - 1)
               lBc%gm%d(:,a,i) = tmp(j+1:j+iDof)
            END DO
         END DO
         DEALLOCATE(tmp)
      END IF

!     Communicating profile data
      flag = ALLOCATED(lBc%gx)
      CALL cm%bcast(flag)
      IF (flag) THEN
         nNo = ib%msh(lBc%iM)%fa(lBc%iFa)%nNo
         IF (cm%slv()) ALLOCATE(lBc%gx(nNo))
         CALL cm%bcast(lBc%gx)
      END IF

      RETURN
      END SUBROUTINE DISTBCIB
!--------------------------------------------------------------------
!     This routine distributes follower loads for shells
      SUBROUTINE DISTSFP(lShlFp)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      TYPE(shlFpType), INTENT(INOUT) :: lShlFp

      LOGICAL flag
      INTEGER j

      CALL cm%bcast(lShlFp%bType)
      CALL cm%bcast(lShlFp%p)

      flag = ALLOCATED(lShlFp%pt)
      IF (flag) THEN
         IF (cm%slv()) ALLOCATE(lShlFp%pt)
         CALL cm%bcast(lShlFp%pt%qi)
         CALL cm%bcast(lShlFp%pt%qs)
         CALL cm%bcast(lShlFp%pt%ti)
         CALL cm%bcast(lShlFp%pt%n)
         CALL cm%bcast(lShlFp%pt%T)
         j = lShlFp%pt%n
         IF (cm%slv()) THEN
            ALLOCATE(lShlFp%pt%r(j))
            ALLOCATE(lShlFp%pt%i(j))
         END IF
         CALL cm%bcast(lShlFp%pt%r)
         CALL cm%bcast(lShlFp%pt%i)
      END IF

      RETURN
      END SUBROUTINE DISTSFP
!!--------------------------------------------------------------------
!     This subroutine distributes constants and parameters of the
!     constitutive model to all processes
      SUBROUTINE DIST_MATCONSTS(lStM)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      TYPE(stModelType), INTENT(INOUT) :: lStM

      CALL cm%bcast(lStM%volType)
      CALL cm%bcast(lStM%Kpen)
      CALL cm%bcast(lStM%isoType)
      CALL cm%bcast(lStM%C01)
      CALL cm%bcast(lStM%C10)
      CALL cm%bcast(lStM%a)
      CALL cm%bcast(lStM%b)
      CALL cm%bcast(lStM%aff)
      CALL cm%bcast(lStM%bff)
      CALL cm%bcast(lStM%ass)
      CALL cm%bcast(lStM%bss)
      CALL cm%bcast(lStM%afs)
      CALL cm%bcast(lStM%bfs)
      CALL cm%bcast(lStM%kap)

      RETURN
      END SUBROUTINE DIST_MATCONSTS
!####################################################################
!     This is for partitioning a single mesh
      SUBROUTINE PARTMSH(lM, gmtl, nP, wgt)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      INTEGER, INTENT(IN) :: nP
      REAL, INTENT(IN) :: wgt(nP)
      INTEGER, INTENT(INOUT) :: gmtl(gtnNo)
      TYPE(mshType), INTENT(INOUT) :: lM

      INTEGER(KIND=MPI_OFFSET_KIND) :: idisp
      LOGICAL :: flag
      INTEGER :: i, a, Ac, e, Ec, edgecut, nEl, nNo, eNoN, eNoNb, ierr,
     2   fid, SPLIT, insd
      CHARACTER(LEN=stdL) fTmp

      INTEGER, ALLOCATABLE :: part(:), gPart(:), tempIEN(:,:),
     2   gtlPtr(:), sCount(:), disp(:)
      REAL(KIND=8), ALLOCATABLE :: tmpR(:)

      IF (cm%seq()) THEN
         lM%nEl = lM%gnEl
         lM%nNo = lM%gnNo
         ALLOCATE(lM%IEN(lM%eNoN,lM%nEl), lM%eDist(0:cm%np()))
         lM%IEN      = lM%gIEN
         lM%eDist(0) = 0
         lM%eDist(1) = lM%gnEl
         ALLOCATE(lM%otnIEN(lM%nEl))
         DO e=1, lM%nEl
            lM%otnIEN(e) = e
         END DO
         ALLOCATE(lM%iGC(lM%nEl))
         lM%iGC = 0
         RETURN
      END IF

!     Sending data from read by master in READFILES to slaves
      CALL cm%bcast(lM%lShpF)
      CALL cm%bcast(lM%lShl)
      CALL cm%bcast(lM%eType)
      CALL cm%bcast(lM%eNoN)
      CALL cm%bcast(lM%nFa)
      CALL cm%bcast(lM%nG)
      CALL cm%bcast(lM%gnEl)
      CALL cm%bcast(lM%gnNo)
      CALL cm%bcast(lM%name)

      insd = nsd
      IF (lM%lShl) insd = nsd - 1

      eNoN = lM%eNoN
      IF (cm%slv()) THEN
         CALL SELECTELE(lM)
         ALLOCATE(lM%gIEN(0,0), lM%fa(lM%nFa))
      END IF
      ALLOCATE(sCount(cm%np()), disp(cm%np()), lM%eDist(0:cm%np()))

!     And distributing bs for NURBS
      IF (lM%eType .EQ. eType_NRB) THEN
         IF (cm%slv()) ALLOCATE(lM%bs(insd))
         CALL cm%bcast(lM%nSl)
         DO i=1, insd
            CALL cm%bcast(lM%bs(i)%n)
            CALL cm%bcast(lM%bs(i)%nG)
            CALL cm%bcast(lM%bs(i)%nEl)
            CALL cm%bcast(lM%bs(i)%nSl)
            CALL cm%bcast(lM%bs(i)%p)
            IF (cm%slv()) ALLOCATE(lM%bs(i)%xi(lM%bs(i)%n))
            CALL cm%bcast(lM%bs(i)%xi)
            lM%bs(i)%nNo = lM%bs(i)%n - lM%bs(i)%p - 1
         END DO

         a = lM%bs(2)%nEl
         IF (insd .EQ. 3) a = a*lM%bs(3)%nEl
         DO i=0, cm%np()
            lM%eDist(i) = NINT(SUM(wgt(1:i))*lM%bs(1)%nEl)*a
            IF (lM%eDist(i) .GT. lM%gnEl) lM%eDist(i) = lM%gnEl
         END DO
      ELSE
!     A draft of splitting the mesh between processors
!     lM%eDist(i) represents first element which belong to cm%id()=i
         DO i=0, cm%np()
            lM%eDist(i) = NINT(SUM(wgt(1:i))*lM%gnEl)
            IF (lM%eDist(i) .GT. lM%gnEl) lM%eDist(i) = lM%gnEl
         END DO
      END IF
      lM%eDist(cm%np()) = lM%gnEl

      DO i=1, cm%np()
         disp(i)   = lM%eDist(i-1)*eNoN
         sCount(i) = lM%eDist(i)*eNoN - disp(i)
      END DO

      nEl = lM%eDist(cm%id() + 1) - lM%eDist(cm%id())
      idisp = lM%eDist(cm%id())*SIZEOF(nEl)
      ALLOCATE(part(nEl))

      fTmp = TRIM(appPath)//".partitioning_"//TRIM(lM%name)//".bin"
      flag = .FALSE.
      IF (rmsh%isReqd) INQUIRE(FILE=TRIM(fTmp), EXIST=flag)
      IF (lM%eType .EQ. eType_NRB) THEN
         part = cm%id()
      ELSE IF (flag .AND. .NOT.resetSim) THEN
         std = " Reading partition data from file"
         CALL MPI_FILE_OPEN(cm%com(), TRIM(fTmp), MPI_MODE_RDONLY,
     2      MPI_INFO_NULL, fid, ierr)
         CALL MPI_FILE_SET_VIEW(fid, idisp, mpint, mpint, 'native',
     2      MPI_INFO_NULL, ierr)
         CALL MPI_FILE_READ(fid, part, nEl, mpint,
     2      MPI_STATUS_IGNORE, ierr)
         CALL MPI_FILE_CLOSE(fid, ierr)
      ELSE
         ALLOCATE(lM%IEN(eNoN,nEl))
!     Scattering the lM%gIEN array to processors
         CALL MPI_SCATTERV(lM%gIEN, sCount, disp, mpint, lM%IEN,
     2      nEl*eNoN, mpint, master, cm%com(), ierr)

!     This is to get eNoNb
         SELECT CASE (lM%eType)
         CASE(eType_BRK)
            eNoNb = 4
         CASE(eType_TET)
            eNoNb = 3
         CASE(eType_WDG)
            eNoNb = 3
         CASE(eType_TRI)
            eNoNb = 2
         CASE(eType_BIL)
            eNoNb = 2
         CASE(eType_BIQ)
            eNoNb = 3
         CASE DEFAULT
            err = "Undefined element type"
         END SELECT
!     The output of this process is "part" array which part(i) says
!     which processor element "i" belongs to
!     Doing partitioning, using ParMetis
         edgecut = SPLIT(nEl, eNoN, eNoNb, lM%IEN, cm%np(), lM%eDist,
     2      wgt, part)
         IF (edgecut .EQ. 0) THEN
c            wrn = " ParMETIS failed to partition the mesh"
            part = cm%id()
         ELSE IF (edgecut .GT. 0) THEN
            std = " ParMETIS partitioned the mesh by cutting "//
     2         STR(edgecut)//" elements"
!     LT 0 is for the case that all elements reside in one processor
         END IF
         DEALLOCATE(lM%IEN)
         IF (rmsh%isReqd) THEN
            std = " Writing partition data to file"
            CALL MPI_FILE_OPEN(cm%com(), TRIM(fTmp), MPI_MODE_WRONLY +
     2         MPI_MODE_CREATE, MPI_INFO_NULL, fid, ierr)
            CALL MPI_FILE_SET_VIEW(fid, idisp, mpint, mpint, 'native',
     2         MPI_INFO_NULL, ierr)
            CALL MPI_FILE_WRITE(fid, part, nEl, mpint,
     2         MPI_STATUS_IGNORE, ierr)
            CALL MPI_FILE_CLOSE(fid, ierr)
         END IF
      END IF

      DO i=1, cm%np()
         disp(i)   = lM%eDist(i-1)
         sCount(i) = lM%eDist(i) - disp(i)
      END DO

!     Gathering the parts inside master, part(e) is equal to the
!     cm%id() that the element e belong to
      IF (cm%mas()) THEN
         ALLOCATE(gPart(lM%gnEl))
      ELSE
         ALLOCATE(gPart(0))
      END IF
!     gpart is a global version of part in which processor p = gpart(e)
!     is the owner of element "e"
      CALL MPI_GATHERV(part, nEl, mpint, gPart, sCount, disp, mpint,
     2   master, cm%com(), ierr)

      DEALLOCATE(part)
      IF (cm%mas()) THEN
         sCount = 0
         DO e=1, lM%gnEl
            sCount(gPart(e) + 1) = sCount(gPart(e) + 1) + 1
         END DO
         DO i=1, cm%np()
            lM%eDist(i) = lM%eDist(i-1) + sCount(i)
         END DO

         ALLOCATE(tempIEN(eNoN,lM%gnEl), lM%otnIEN(lM%gnEl))
!     Making the lM%IEN array in order, based on the cm%id() number in the
!     master. lM%otnIEN maps old IEN order to new IEN order.
         disp = 0
         DO e=1, lM%gnEl
            Ec = lM%eDist(gPart(e)) + 1
            lM%eDist(gPart(e)) = Ec
            tempIEN(:,Ec) = lM%gIEN(:,e)
            lM%otnIEN(e) = Ec
         END DO
         lM%gIEN = tempIEN
         lM%eDist(0) = 0
         DO i=1, cm%np()
            lM%eDist(i) = lM%eDist(i-1) + sCount(i)
         END DO

!     This it to distribute eId, if allocated
         flag = .FALSE.
         IF (ALLOCATED(lM%eId)) THEN
            flag = .TRUE.
            ALLOCATE(part(lM%gnEl))
            DO e=1, lM%gnEl
               Ec = lM%otnIEN(e)
               part(Ec) = lM%eId(e)
            END DO
            DEALLOCATE(lM%eId)
         END IF
      ELSE
         ALLOCATE(lM%otnIEN(0))
      END IF
      DEALLOCATE(gPart)

      CALL cm%bcast(flag)
      CALL cm%bcast(lM%eDist)

      nEl = lM%eDist(cm%id() + 1) - lM%eDist(cm%id())
      lM%nEl = nEl
      ALLOCATE(lM%IEN(eNoN,nEl), lM%iGC(nEl))
      lM%iGC = 0

!     Communicating eId, if neccessary
      IF (flag) THEN
         ALLOCATE(lM%eId(nEl))
         IF (.NOT.ALLOCATED(part)) ALLOCATE(part(0))
         DO i=1, cm%np()
            disp(i)   = lM%eDist(i-1)
            sCount(i) = lM%eDist(i) - disp(i)
         END DO
         CALL MPI_SCATTERV(part, sCount, disp, mpint, lM%eId, nEl,
     2      mpint, master, cm%com(), ierr)
         DEALLOCATE(part)
      END IF

!     Now scattering the sorted lM%IEN to all processors
      IF (.NOT.ALLOCATED(tempIEN)) ALLOCATE(tempIEN(0,0))
      DO i=1, cm%np()
         disp(i)   = lM%eDist(i-1)*eNoN
         sCount(i) = lM%eDist(i)*eNoN - disp(i)
      END DO
      CALL MPI_SCATTERV(tempIEN, sCount, disp, mpint, lM%IEN, nEl*eNoN,
     2   mpint, master, cm%com(), ierr)
      DEALLOCATE(tempIEN)

!     Constructing the initial global to local pointer
!     lM%IEN: eNoN,nEl --> gnNo
!     gtlPtr: gnNo     --> nNo
!     lM%IEN: eNoN,nEl --> nNo
      ALLOCATE(gtlPtr(lM%gnNo))
      nNo    = 0
      gtlPtr = 0
      DO e=1, nEl
         DO a=1, eNoN
            Ac = lM%IEN(a,e)
            IF (gtlPtr(Ac) .EQ. 0) THEN
               nNo = nNo + 1
               gtlPtr(Ac) = nNo
            END IF
            lM%IEN(a,e) = gtlPtr(Ac)
         END DO
      END DO
      lM%nNo = nNo
      IF (cm%slv()) ALLOCATE(lM%gN(lM%gnNo))
      CALL cm%bcast(lM%gN)
!     lM%gN: gnNo --> gtnNo
!     part:  nNo  --> gtnNo
      ALLOCATE(part(nNo))
      DO Ac=1, lM%gnNo
         a = gtlPtr(Ac)
         IF (a .NE. 0) part(a) = lM%gN(Ac)
      END DO
!     mapping and converting other parameters.
!     I will use an upper bound for gPart as a container for ltg,
!     since there can be repeated nodes. gPart is just a temp variable.
!     gmtl:  gtnNo --> tnNo
!     gPart: tnNo  --> gtnNo
!     ltg:   tnNo  --> gtnNo
!     lM%gN: nNo   --> tnNo
      DEALLOCATE(lM%gN)
      ALLOCATE(gPart(tnNo+nNo), lM%gN(nNo))
      DO a=1, tnNo
         Ac       = ltg(a)
         gPart(a) = Ac
         gmtl(Ac) = a
      END DO
      DO a=1, nNo
         Ac = part(a)
         IF (gmtl(Ac) .EQ. 0) THEN
            tnNo        = tnNo + 1
            gmtl(Ac)    = tnNo
            lM%gN(a)    = tnNo
            gPart(tnNo) = Ac
         ELSE
            lM%gN(a) = gmtl(Ac)
         END IF
      END DO
      IF (ALLOCATED(ltg)) DEALLOCATE(ltg)
      ALLOCATE(ltg(tnNo))
      ltg = gPart(1:tnNo)
      DEALLOCATE(gPart)

!     If neccessary communicate NURBS
      IF (lM%eType .EQ. eType_NRB) THEN
         ALLOCATE(tmpR(lM%gnNo))
         IF (cm%mas()) THEN
            tmpR = lM%nW
            DEALLOCATE(lM%nW)
         END IF
         CALL cm%bcast(tmpR)
         ALLOCATE(lM%nW(lM%nNo))
         DO Ac=1, lM%gnNo
            a = gtlPtr(Ac)
            IF (a .NE. 0) THEN
               lM%nW(a) = tmpR(Ac)
            END IF
         END DO
!     Distributing INN, using tempIEN as tmp array
         IF (cm%mas()) THEN
            ALLOCATE(tempIEN(insd,lM%gnEl))
            DO e=1, lM%gnEl
               Ec = lM%otnIEN(e)
               tempIEN(:,Ec) = lM%INN(:,e)
            END DO
            DEALLOCATE(lM%INN)
         ELSE
            ALLOCATE(tempIEN(0,0))
         END IF
         DO i=1, cm%np()
            disp(i)   = lM%eDist(i-1)*insd
            sCount(i) = lM%eDist(i)*insd - disp(i)
         END DO
         ALLOCATE(lM%INN(insd,nEl))
!     Now scattering the sorted lM%INN to all processors
         CALL MPI_SCATTERV(tempIEN, sCount, disp, mpint, lM%INN,
     2      nEl*insd, mpint, master, cm%com(), ierr)
      END IF

      RETURN
      END SUBROUTINE PARTMSH
!--------------------------------------------------------------------
!     This routine partitions the face based on the already partitioned
!     mesh
      SUBROUTINE PARTFACE(lM, lFa, gFa, gmtl)
      USE COMMOD
      USE ALLFUN
      IMPLICIT NONE

      TYPE(mshType), INTENT(INOUT) :: lM
      TYPE(faceType), INTENT(INOUT) :: lFa, gFa
      INTEGER, INTENT(IN) :: gmtl(gtnNo)

      INTEGER eNoNb, e, a, Ac, Ec, i, j

      INTEGER, ALLOCATABLE :: part(:), ePtr(:)

!     Broadcasting the number of nodes and elements of to slaves and
!     populating gFa to all procs
      IF (cm%mas()) THEN
         gFa%d    = lFa%d
         gFa%nNo  = lFa%nNo
         gFa%nEl  = lFa%nEl
         gFa%eNoN = lFa%eNoN
         gFa%gnEl = lFa%gnEl
         IF (rmsh%isReqd) ALLOCATE(gFa%gebc(1+gFa%eNoN,gFa%gnEl))
      ELSE
         IF (rmsh%isReqd) ALLOCATE(gFa%gebc(0,0))
      END IF
      CALL cm%bcast(gFa%d)
      CALL cm%bcast(gFa%nNo)
      CALL cm%bcast(gFa%nEl)
      CALL cm%bcast(gFa%eNoN)
      CALL cm%bcast(gFa%gnEl)
      CALL SELECTELEB(lM, gFa)

      eNoNb = gFa%eNoN
      ALLOCATE(gFa%IEN(eNoNb,gFa%nEl), gFa%gE(gFa%nEl), gFa%gN(gFa%nNo),
     2   ePtr(gFa%nEl))
      IF (cm%mas()) THEN
         gFa = lFa
         CALL DESTROY(lFa)
      END IF
      CALL cm%bcast(gFa%name)
      lFa%name = gFa%name
      lFa%d    = gFa%d
      lFa%eNoN = eNoNb
      CALL SELECTELEB(lM, lFa)

      i = gFa%nEl*(2+eNoNb) + gFa%nNo
      ALLOCATE(part(i))
      IF (cm%mas()) THEN
         DO e=1, gFa%nEl
            j  = (e-1)*(2+eNoNb) + 1
            Ec = gFa%gE(e)
            ePtr(e)   = lM%otnIEN(Ec)
            part(j)   = Ec
            part(j+1) = ePtr(e)
            part(j+2:j+1+eNoNb) = gFa%IEN(:,e)
         END DO
         DO a=1, gFa%nNo
            j = gFa%nEl*(2+eNoNb) + a
            part(j) = gFa%gN(a)
         END DO
      END IF

      CALL cm%bcast(part)
      IF (cm%slv()) THEN
         DO e=1, gFa%nEl
            j = (e-1)*(2+eNoNb) + 1
            gFa%gE(e)    = part(j)
            ePtr(e)      = part(j+1)
            gFa%IEN(:,e) = part(j+2:j+1+eNoNb)
         END DO
         DO a=1, gFa%nNo
            j = gFa%nEl*(2+eNoNb) + a
            gFa%gN(a) = part(j)
         END DO
      END IF
      DEALLOCATE(part)

!     Finding the number of lM%fas to allocate required space, also
!     maping global element number to processor element number
      lFa%nEl = 0
      DO e=1, gFa%nEl
         Ec = ePtr(e)
         gFa%gE(e) = Ec
         IF (Ec.LE.lM%eDist(cm%id()+1) .AND.
     2       Ec.GT.lM%eDist(cm%id()) ) THEN
            lFa%nEl = lFa%nEl + 1
         END IF
      END DO
      ALLOCATE(lFa%gE(lFa%nEl), lFa%IEN(eNoNb,lFa%nEl))
      lFa%nNo = 0
      DO a=1, gFa%nNo
         Ac = gmtl(gFa%gN(a))
         IF (Ac .NE. 0) THEN
            lFa%nNo = lFa%nNo + 1
         END IF
      END DO
      ALLOCATE(lFa%gN(lFa%nNo))

!     Time to form "face" structure in each processor
!     Only copying the element which belong to this processors
      j = 0
      DO e=1, gFa%nEl
         Ec = gFa%gE(e)
         IF (Ec.LE.lM%eDist(cm%id()+1) .AND.
     2       Ec.GT.lM%eDist(cm%id())) THEN
            j = j + 1
            lFa%gE(j) = Ec - lM%eDist(cm%id())
            DO a=1, eNoNb
               lFa%IEN(a,j) = gmtl(gFa%IEN(a,e))
            END DO
         END IF
      END DO
!     Analogously copying the nodes which belong to this processor
      j = 0
      DO a=1, gFa%nNo
         Ac = gmtl(gFa%gN(a))
         IF (Ac .NE. 0) THEN
            j = j + 1
            lFa%gN(j) = Ac
         END IF
      END DO

      lFa%gnEl = gFa%gnEl
      IF (rmsh%isReqd) THEN
         IF(cm%mas()) THEN
            ALLOCATE(lFa%gebc(1+eNoNb,lFa%gnEl))
            DO e=1, gFa%gnEl
               lFa%gebc(1,e) = gFa%gebc(1,e)
               lFa%gebc(2:1+eNoNb,e) = gFa%gebc(2:1+eNoNb,e)
            END DO
         ELSE
            ALLOCATE(lFa%gebc(0,0))
         END IF
      END IF

      RETURN
      END SUBROUTINE PARTFACE
!####################################################################
