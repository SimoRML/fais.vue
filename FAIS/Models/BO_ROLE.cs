//------------------------------------------------------------------------------
// <auto-generated>
//     Ce code a été généré à partir d'un modèle.
//
//     Des modifications manuelles apportées à ce fichier peuvent conduire à un comportement inattendu de votre application.
//     Les modifications manuelles apportées à ce fichier sont remplacées si le code est régénéré.
// </auto-generated>
//------------------------------------------------------------------------------

namespace FAIS.Models
{
    using System;
    using System.Collections.Generic;
    
    public partial class BO_ROLE
    {
        public long BO_ROLE_ID { get; set; }
        public long META_BO_ID { get; set; }
        public string ROLE_ID { get; set; }
        public Nullable<bool> CAN_READ { get; set; }
        public Nullable<bool> CAN_WRITE { get; set; }
        public string CREATED_BY { get; set; }
        public Nullable<System.DateTime> CREATED_DATE { get; set; }
        public string UPDATED_BY { get; set; }
        public Nullable<System.DateTime> UPDATED_DATE { get; set; }
        public string STATUS { get; set; }
    }
}
