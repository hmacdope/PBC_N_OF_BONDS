!=============================================================================
!============================= N_OF_BONDS ====================================
!=============================================================================
double precision pure function f6_12_value(x)

   use nfe_lib_mod, only : ONE

   implicit none

   double precision, intent(in) :: x

   f6_12_value = ONE/(ONE + x**3)

end function f6_12_value

!=============================================================================

double precision pure function f6_12_derivative(x)

   use nfe_lib_mod, only : ONE

   implicit none

   double precision, parameter :: MINUS_THREE = -3.000000000000000000000D0 ! dble(-3)

   double precision, intent(in) :: x

   double precision :: x2, tmp

   x2 = x*x
   tmp = ONE + x*x2

   f6_12_derivative = MINUS_THREE*x2/(tmp*tmp)

end function f6_12_derivative

!=============================================================================

subroutine partition(cv, first, last)

   NFE_USE_AFAILED

   use parallel_dat_mod

   implicit none

   type(colvar_t), intent(in) :: cv
   integer, intent(out) :: first, last

#  ifdef MPI
   integer :: tmp
#  endif /* MPI */

   nfe_assert(cv%type == COLVAR_N_OF_BONDS)
   nfe_assert(associated(cv%i))
   nfe_assert(mod(size(cv%i), 2).eq.0)

#  ifdef MPI
   tmp = (size(cv%i)/2)/numtasks
   if (tmp.gt.0) then
      if (mytaskid.eq.(numtasks - 1)) then
         first = 2*tmp*mytaskid + 1
         last = size(cv%i) - 1
      else
         first = 2*tmp*mytaskid + 1
         last = 2*(mytaskid + 1)*tmp - 1
      end if
   else
      if (mytaskid.eq.(numtasks - 1)) then
         first = 1
         last = size(cv%i) - 1
      else
         first = 1
         last = 0
      end if
   end if
#  else
   first = 1
   last = size(cv%i) - 1
#  endif /* MPI */

end subroutine partition

!=============================================================================
!Feng Pan and Hugo MacDermott-Opeskin

function v_N_OF_BONDS(cv, x) result(value)

   use nfe_lib_mod
   use parallel_dat_mod

   implicit none

   double precision :: value

   type(colvar_t), intent(inout) :: cv

   double precision, intent(in) :: x(*)

#  ifdef MPI
   integer :: error
   double precision :: accu
#  endif /* MPI */

   integer :: first, last
   integer :: i, i3, j3

   double precision :: r2
   double precision, parameter :: d0 = ONE

   nfe_assert(cv%type == COLVAR_N_OF_BONDS)

   nfe_assert(associated(cv%i))
   nfe_assert(associated(cv%r))
   nfe_assert(mod(size(cv%i), 2).eq.0)
  
   value = ZERO
 
   call partition(cv, first, last)
 
   do i = first, last, 2
      i3 = 3*cv%i(i) - 2
      j3 = 3*cv%i(i + 1) - 2
      r2 = (PBC_distance(x(i3:i3+2), x(j3:j3+2), d0))**2
      r2 = r2/cv%r(1)**2
      value = value + f6_12_value(r2)

   end do


#  ifdef MPI
   call mpi_reduce(value, accu, 1, MPI_DOUBLE_PRECISION, &
                   MPI_SUM, 0, pmemd_comm, error)
   nfe_assert(error.eq.0)
   value = accu
#  endif /* MPI */

end function v_N_OF_BONDS

!=============================================================================
!Feng Pan and Hugo MacDermott-Opeskin
subroutine f_N_OF_BONDS(cv, x, fcv, f)

   use nfe_lib_mod
   use parallel_dat_mod

   implicit none

   type(colvar_t), intent(in) :: cv

   double precision, intent(in) :: x(*), fcv
   double precision, intent(inout) :: f(*)

   integer   :: i, i3, j3, k

   double precision :: r2, tmp, r
   double precision :: dxf1(3), dxf2(3), dx1(3), dx2(3)
   double precision, parameter :: d0 = ONE

#ifdef MPI
   integer :: error
#endif /* MPI */

   nfe_assert(cv%type == COLVAR_N_OF_BONDS)

   nfe_assert(associated(cv%i))
   nfe_assert(associated(cv%r))

   ! beyond this point  everything done on master, making it slow

   NFE_MASTER_ONLY_BEGIN
   
   do i = 1, size(cv%i), 2

      i3 = 3*cv%i(i) - 2
      j3 = 3*cv%i(i + 1) - 2
      !find the distance
      r = PBC_distance(x(i3:i3 + 2), x(j3:j3 + 2), d0)
      !find the unit displacement vectors
      call PBC_distance_d(x(i3:i3 + 2), x(j3:j3 + 2), d0, dx1, dx2)
      !calculate the displacement i to j 
      do k = 1,3
        dxf1(k) = r*dx1(k)
        dxf2(k) = r*dx2(k)
      end do
      !r2
      r2 = (r**2)/(cv%r(1)**2)

      tmp = (2*fcv/cv%r(1)**2)*f6_12_derivative(r2)

      dxf1(1) = tmp*dxf1(1)
      dxf2(1) = tmp*dxf2(1)
      f(i3 + 0) = f(i3 + 0) + dxf1(1)
      f(j3 + 0) = f(j3 + 0) + dxf2(1)

      dxf1(2) = tmp*dxf1(2)
      dxf2(2) = tmp*dxf2(2)
      f(i3 + 1) = f(i3 + 1) + dxf1(2)
      f(j3 + 1) = f(j3 + 1) + dxf2(2)

      dxf1(3) = tmp*dxf1(3)
      dxf2(3) = tmp*dxf2(3)
      f(i3 + 2) = f(i3 + 2) + dxf1(3)
      f(j3 + 2) = f(j3 + 2) + dxf2(3)

   end do
   NFE_MASTER_ONLY_END

   
#ifdef MPI
   call mpi_bcast(f(1:3*pmemd_natoms()), 3*pmemd_natoms(), MPI_DOUBLE_PRECISION, 0, pmemd_comm, error)
   nfe_assert(error.eq.0)
#endif /* MPI */
end subroutine f_N_OF_BONDS


!=============================================================================

subroutine b_N_OF_BONDS(cv, cvno, amass)

   use nfe_lib_mod
   use parallel_dat_mod

   implicit none

   type(colvar_t), intent(inout) :: cv
   integer,        intent(in)    :: cvno
   double precision,      intent(in)    :: amass(*)
   integer :: a

   nfe_assert(cv%type == COLVAR_N_OF_BONDS)

   if (.not.associated(cv%i)) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, ' (N_OF_BONDS) : no integers'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! .not.associated(cv%i)

   if (size(cv%i).lt.2) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, ' (N_OF_BONDS) : too few integers'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! size(cv%i).lt.3

   if (mod(size(cv%i), 2).ne.0) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, &
            ' (N_OF_BONDS) : number of integers is odd'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! sep.eq.size(cv%i)

   do a = 1, size(cv%i) - 1, 2
      if (cv%i(a).lt.1.or.cv%i(a).gt.pmemd_natoms()) then
         NFE_MASTER_ONLY_BEGIN
            write (unit = ERR_UNIT, &
               fmt = '(/a,a,'//pfmt(cvno)//',a,'//pfmt &
              (a)//',a,'//pfmt(cv%i(a))//',a,'//pfmt(pmemd_natoms())//',a/)') &
               NFE_ERROR, 'CV #', cvno, &
               ' (N_OF_BONDS) : integer #', a, ' (', cv%i(a), &
               ') is out of range [1, ', pmemd_natoms(), ']'
         NFE_MASTER_ONLY_END
         call terminate()
      end if
      if (cv%i(a + 1).lt.1.or.cv%i(a + 1).gt.pmemd_natoms()) then
         NFE_MASTER_ONLY_BEGIN
            write (unit = ERR_UNIT, &
               fmt = '(/a,a,'//pfmt(cvno)//',a,'//pfmt &
               (a + 1)//',a,'//pfmt(cv%i(a + 1))//',a,'//pfmt &
               (pmemd_natoms())//',a/)') &
               NFE_ERROR, 'CV #', cvno, &
               ' (N_OF_BONDS) : integer #', a + 1, ' (', cv%i(a + 1), &
               ') is out of range [1, ', pmemd_natoms(), ']'
         NFE_MASTER_ONLY_END
         call terminate()
      end if
      if (cv%i(a).eq.cv%i(a + 1)) then
         NFE_MASTER_ONLY_BEGIN
            write (unit = ERR_UNIT, &
               fmt = '(/a,a,'//pfmt(cvno)//',a,'//pfmt &
               (a)//',a,'//pfmt(a + 1)//',a,'//pfmt(cv%i(a))//',a/)') &
               NFE_WARNING, 'CV #', cvno, &
               ' (N_OF_BONDS) : integers #', a, ' and ', a + 1, &
               ' are equal (', cv%i(a), ')'
         NFE_MASTER_ONLY_END
      end if
   end do

   if (.not.associated(cv%r)) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, ' (N_OF_BONDS) : no reals found'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! .not. associated(cvi)

   if (size(cv%r).ne.1) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, ' (N_OF_BONDS) : number of reals is not 1'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! .not. associated(cvi)

   if (cv%r(1).le.ZERO) then
      NFE_MASTER_ONLY_BEGIN
         write (unit = ERR_UNIT, fmt = '(/a,a,'//pfmt(cvno)//',a/)') &
            NFE_ERROR, 'CV #', cvno, ' (N_OF_BONDS) : r(1).le.0.0D0 is .true.'
      NFE_MASTER_ONLY_END
      call terminate()
   end if ! .not. associated(cvi)

end subroutine b_N_OF_BONDS

!=============================================================================

subroutine p_N_OF_BONDS(cv, lun)

   use nfe_lib_mod

   implicit none

   type(colvar_t), intent(in) :: cv
   integer, intent(in) :: lun

   integer :: a
   character(4) :: aname

   nfe_assert(cv%type == COLVAR_N_OF_BONDS)

   nfe_assert(associated(cv%i))
   nfe_assert(associated(cv%r))

   nfe_assert(mod(size(cv%i), 2).eq.0)

   write (unit = lun, fmt = '(a,a,'//pfmt(cv%r(1), 3)//')') &
      NFE_INFO, '    d0 = ', cv%r(1)
   write (unit = lun, fmt = '(a,a)', advance = 'NO') NFE_INFO, ' pairs = ('

   do a = 1, size(cv%i)

      nfe_assert(cv%i(a).gt.0.and.cv%i(a).le.pmemd_natoms())
      aname = pmemd_atom_name(cv%i(a))

      write (unit = lun, fmt = '('//pfmt(cv%i(a))//',a,a,a)', advance = 'NO') &
         cv%i(a), ' [', trim(aname), ']'

      if (a.eq.size(cv%i)) then
         write (unit = lun, fmt = '(a)') ')'
      else if (mod(a, 4).eq.0) then
         write (unit = lun, fmt = '(a,/a,10x)', advance = 'NO') ',', NFE_INFO
      else if (mod(a, 2).eq.1) then
         write (unit = lun, fmt = '(a)', advance = 'NO') ' <=> '
      else
         write (unit = lun, fmt = '(a)', advance = 'NO') ', '
      end if

   end do

end subroutine p_N_OF_BONDS

!=============================================================================