//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated from a template.
//
//     Manual changes to this file may cause unexpected behavior in your application.
//     Manual changes to this file will be overwritten if the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

namespace FAIS.Models
{
    using System;
    using System.Collections.Generic;
    
    public partial class META_FIELD
    {
        public long META_FIELD_ID { get; set; }
        public long META_BO_ID { get; set; }
        public string DB_NAME { get; set; }
        public string DB_TYPE { get; set; }
        public int DB_NULL { get; set; }
        public string GRID_NAME { get; set; }
        public string GRID_FORMAT { get; set; }
        public Nullable<int> GRID_SHOW { get; set; }
        public string FORM_NAME { get; set; }
        public string FORM_FORMAT { get; set; }
        public string FORM_TYPE { get; set; }
        public string FORM_SOURCE { get; set; }
        public Nullable<int> FORM_SHOW { get; set; }
        public Nullable<int> FORM_OPTIONAL { get; set; }
        public string CREATED_BY { get; set; }
        public Nullable<System.DateTime> CREATED_DATE { get; set; }
        public string UPDATED_BY { get; set; }
        public Nullable<System.DateTime> UPDATED_DATE { get; set; }
        public string STATUS { get; set; }
    }
}
