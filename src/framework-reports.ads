----------------------------------------------------------------------
--  Framework.Reports - Package specification                       --
--                                                                  --
--  This software  is (c) The European Organisation  for the Safety --
--  of Air  Navigation (EUROCONTROL) and Adalog  2004-2005. The Ada --
--  Controller  is  free software;  you can redistribute  it and/or --
--  modify  it under  terms of  the GNU  General Public  License as --
--  published by the Free Software Foundation; either version 2, or --
--  (at your  option) any later version.  This  unit is distributed --
--  in the hope  that it will be useful,  but WITHOUT ANY WARRANTY; --
--  without even the implied warranty of MERCHANTABILITY or FITNESS --
--  FOR A  PARTICULAR PURPOSE.  See the GNU  General Public License --
--  for more details.   You should have received a  copy of the GNU --
--  General Public License distributed  with this program; see file --
--  COPYING.   If not, write  to the  Free Software  Foundation, 59 --
--  Temple Place - Suite 330, Boston, MA 02111-1307, USA.           --
--                                                                  --
--  As  a special  exception, if  other files  instantiate generics --
--  from the units  of this program, or if you  link this unit with --
--  other files  to produce  an executable, this  unit does  not by --
--  itself cause the resulting executable  to be covered by the GNU --
--  General  Public  License.   This  exception  does  not  however --
--  invalidate any  other reasons why the executable  file might be --
--  covered by the GNU Public License.                              --
--                                                                  --
--  This  software is  distributed  in  the hope  that  it will  be --
--  useful,  but WITHOUT  ANY  WARRANTY; without  even the  implied --
--  warranty  of  MERCHANTABILITY   or  FITNESS  FOR  A  PARTICULAR --
--  PURPOSE.                                                        --
----------------------------------------------------------------------

package Framework.Reports is

   procedure Report (Rule_Id   : in Wide_String;
                     Ctl_Label : in Wide_String;
                     Ctl_Kind  : in Control_Kinds;
                     Loc       : in Location;
                     Msg       : in Wide_String);
   -- Reports rule match to current output

   procedure Report (Rule_Id    : in Wide_String;
                     Context    : in Root_Context'Class;
                     Loc        : in Location;
                     Msg        : in Wide_String;
                     Count_Only : in Boolean := False);
   -- Id, but get Rule_Label and Rule_Type from Context
   -- Context must be either No_Matching_Context (and Report does nothing)
   --   or a descendant of Simple_Context.

   procedure Uncheckable (Rule_Id : in Wide_String;
                          Risk    : in Uncheckable_Consequence;
                          Loc     : in Location;
                          Msg     : in Wide_String);
   -- Called when a rule cannot check something, because f.e. it depends on a non
   -- statically analyzable construct

   Cancellation : exception;
   -- Raised when the number of allowed errors/messages is exceeded
   -- Occurrence message gives the exact cause


   ----------------------------------------------------------------------------------------
   --
   --  Declarations below this line are for the use of the framework
   --
   use Ada.Strings.Wide_Unbounded;

   -- These two procedures are for the rule Uncheckable
   procedure Set_Uncheckable (Risk : Uncheckable_Consequence; Ctl_Kind : Control_Kinds; Label : Wide_String);
   procedure Reset_Uncheckable;

   function "and" (Left, Right : Wide_String) return Wide_String;
   -- Concatenates the strings, separated by the separator appropriate to the output format

   procedure Raw_Report (Message : Wide_String);

   type Output_Format is (Source, Gnat, CSV, CSVX, None);
   type Stats_Levels  is (None, General, Nulls_Only, Full);
   Warning_As_Error_Option : Boolean       := False;
   Skip_Warning_Option     : Boolean       := False;
   Format_Option           : Output_Format := Gnat;
   Stats_Level             : Stats_Levels  := None;

   Just_Created            : Boolean := False;
   Adactl_Tag1             : Unbounded_Wide_String := To_Unbounded_Wide_String ("##");
   Adactl_Tag2             : Unbounded_Wide_String := To_Unbounded_Wide_String ("##");
   Max_Messages            : Natural := Natural'Last;
   Max_Errors              : Natural := Natural'Last;


   function Nb_Errors   return Natural;
   function Nb_Warnings return Natural;

   procedure Clear (Rule : Wide_String);
   procedure Clear_All;
   procedure Reset;

   procedure Init_Counts (Rule : Wide_String; Label : Wide_String);
   procedure Report_Counts;

   procedure Init_Stats  (Rule : Wide_String; Label : Wide_String);
   procedure Report_Stats;
end Framework.Reports;
