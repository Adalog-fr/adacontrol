----------------------------------------------------------------------
--  Framework.Fixes - Package specification                         --
--                                                                  --
--  This software is (c) Adalog 2004-2016.                          --
--  The Ada Controller is  free software; you can  redistribute  it --
--  and/or modify it under  terms of the GNU General Public License --
--  as published by the Free Software Foundation; either version 2, --
--  or (at your option) any later version. This unit is distributed --
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
----------------------------------------------------------------------

-- Ada
private with
    Ada.Strings.Wide_Unbounded;

-- Asis
with
   Asis,
   Asis.Text;

-- Adalog
private with
   Linear_Queue;

package Framework.Fixes is
   procedure Set_Patch_File (File_Name : Wide_String);

   function "and" (Left : Wide_String; Right : Wide_String) return Wide_String;
   -- Returns the concatenation of the Left and Right, separated by an indication of a line break

   procedure Message (Text : Wide_String);

   procedure Replace (Original : Asis.Element;                     By : Wide_String);
   procedure Replace (Original : Asis.Element;                     By : Asis.Element);
   procedure Replace (Original : Asis.Element;                     By : Asis.Element_List);
   procedure Replace (From     : Location;     Length : Positive ; By : Wide_String);

   type Insert_Place is (Before, After);
   procedure Insert (Text : Wide_String; Place : Insert_Place; Elem : Asis.Element; Full_Line : Boolean := False);
   procedure Insert (Text : Wide_String; From  : Location);
   -- Insert at From characters (can be outside original line, spaces added as needed)

   procedure Break (Place : Location; Indent_New : Asis.Text.Character_Position);

   procedure Delete (Elem  : Asis.Element);
   procedure Delete (Elems : Asis.Element_List);
   procedure Delete (From  : Location; To : Location);
   -- From included, To excluded
   -- Note: To is excluded so that a deletion up to an element does not have to search the preceding element,
   --       which could be on a previous line.

   procedure List_Remove (Inx : Asis.List_Index; From : Asis.Element);
   -- From is expected to be an element accepting a list of names (like a with clause
   -- or a use clause);
   -- Inx is the index of the element to be removed from From
   -- The element is removed from From; however, if it was the last element in From, then From
   -- is deleted in whole.

   -- An Incremental_Fix accumulates (in order) several inserts at the same place
   -- The fix is emitted (and the Incremental_Fix is reset) by calling Flush
   type Incremental_Fix is private;
   procedure Insert (Fix : in out Incremental_Fix; Text : Wide_String; Place : Insert_Place; Elem : Asis.Element);
   procedure Flush  (Fix : in out Incremental_Fix);

private
   type Delayed_Fix is
      record
         Place : Insert_Place;
         Elem  : Asis.Element;
         Text  : Ada.Strings.Wide_Unbounded.Unbounded_Wide_String;
      end record;

   package Fix_List is new Linear_Queue (Delayed_Fix);
   type Incremental_Fix is new Fix_List.Queue;
end Framework.Fixes;
